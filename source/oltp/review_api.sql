create or replace package review_api is
   function dlq_level(in_status in varchar2) return number deterministic;

   procedure generate_candidates(
      in_release_id in varchar2
      , in_reporting_month in date
      , in_rule_code in varchar2
      , out_created out pls_integer
   );

end review_api;
/

create or replace package body review_api is

   function dlq_level(in_status in varchar2) return number deterministic is
      pragma udf;
   begin
      return case
         when in_status = 'RA' then 99
         when regexp_like(in_status, '^[0-9]+$') then to_number(in_status)
      end;
   end dlq_level;
   procedure generate_candidates(
      in_release_id in varchar2
      , in_reporting_month in date
      , in_rule_code in varchar2
      , out_created out pls_integer
   ) is
      l_rule_id review_rule.rule_id%type;
      l_rule_version_id review_rule_version.rule_version_id%type;
      l_min_status review_rule_version.min_delinquency_status%type;
   begin
      select rule_id
      into l_rule_id
      from review_rule
      where rule_code = in_rule_code and is_active = 'Y';
      select
         rule_version_id
         , min_delinquency_status
      into l_rule_version_id, l_min_status
      from review_rule_version
      where rule_id = l_rule_id and effective_from <= in_reporting_month
      order by effective_from desc, version_no desc
      fetch first 1 row only;

      insert into review_candidate (
         rule_version_id
         , data_source
         , loan_identifier
         , reporting_month
         , delinquency_status
         , source_release_id
      )
      with

      params as (
         select
            l_rule_version_id as rule_version_id
            , l_min_status as min_status
            , in_release_id as release_id
         from dual
      )

      , two_months as (
         select
            data_source
            , loan_identifier
            , monthly_reporting_period
            , current_loan_delinquency_status
            , review_api.dlq_level(current_loan_delinquency_status) as dlq_level
         from loan_dw.dwd_loan_monthly_perf
         where
            release_id = in_release_id
            and monthly_reporting_period in (
               add_months(in_reporting_month, -1), in_reporting_month
            )
      )

      , this_month as (
         select
            data_source
            , loan_identifier
            , monthly_reporting_period
            , current_loan_delinquency_status
            , dlq_level
         from two_months
         where monthly_reporting_period = in_reporting_month
      )

      , prev_month as (
         select
            data_source
            , loan_identifier
            , dlq_level
         from two_months
         where monthly_reporting_period = add_months(in_reporting_month, -1)
      )

      select
         p.rule_version_id
         , t.data_source
         , t.loan_identifier
         , t.monthly_reporting_period
         , t.current_loan_delinquency_status
         , p.release_id
      from this_month t
      cross join params p
      left join prev_month pm
         on
            t.data_source = pm.data_source
            and t.loan_identifier = pm.loan_identifier
      where
         t.dlq_level >= p.min_status
         and coalesce(pm.dlq_level, 0) < p.min_status
         and not exists (
            select 1
            from review_candidate c
            where
               c.rule_version_id = p.rule_version_id
               and c.data_source = t.data_source
               and c.loan_identifier = t.loan_identifier
               and c.reporting_month = t.monthly_reporting_period
         );
      out_created := sql%rowcount;
   end generate_candidates;

end review_api;
/
