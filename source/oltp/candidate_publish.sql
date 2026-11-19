-- Name: candidate_publish.sql
-- Purpose: package candidate_publish: apply the review rule to one release and reporting month of the warehouse,
--          and fill the three candidate stage tables with candidates, their evidence, and up to 13 months of history.
--          1. stage_month: pick loans that entered the rule's delinquency level this month (same rule as review_api.generate_candidates),
--             copy their origination fields from dim_loan and their monthly history from dwd_loan_monthly_perf, then call seal
--          2. seal: compute each evidence row's content digest and return the delivery manifest (scope, rule, row counts, content digest)
--          python/candidate_import.py calls stage_month, checks the staged rows independently, and merges them into the review tables
--          in one transaction; identical content gives an identical manifest, so a repeated run changes nothing.
-- Requires: candidate_delivery.sql (stage tables); grant_dw_to_oltp.sql (select on dwd_loan_monthly_perf and dim_loan)
-- Called by: python/candidate_import.py, as loan_oltp
-- Note: the procedures do not commit; the stage tables are session-private and empty at commit.
--       Digest text: evidence columns in contract order joined by '|', then '#', then each month's columns joined by '|',
--       months joined by ';' in date order; numbers as fixed text with three decimals, dates as YYYY-MM-DD, NULL as empty text.

create or replace package candidate_publish is
   -- Fill the stage tables for one release and reporting month (first day of the month) and return the manifest JSON
   procedure stage_month(
      in_release_id in varchar2
      , in_reporting_month in date
      , in_rule_code in varchar2
      , out_manifest out varchar2
   );

   -- Recompute digests and the manifest from the current stage rows (stage_month calls it last)
   procedure seal(
      in_release_id in varchar2
      , in_reporting_month in date
      , in_rule_version_id in number
      , out_manifest out varchar2
   );
end candidate_publish;
/

create or replace package body candidate_publish is

   procedure stage_month(
      in_release_id in varchar2
      , in_reporting_month in date
      , in_rule_code in varchar2
      , out_manifest out varchar2
   ) is
      l_rule_id review_rule.rule_id%type;
      l_rule_version_id review_rule_version.rule_version_id%type;
      l_version_no review_rule_version.version_no%type;
      l_min_status review_rule_version.min_delinquency_status%type;
      l_month_rows pls_integer;
   begin
      if in_reporting_month is null or in_reporting_month != trunc(in_reporting_month, 'MM') then
         raise_application_error(-20601, 'Reporting month must be the first day of a month');
      end if;
      -- Same rule version as review_api.generate_candidates: the latest version effective in this month
      select rule_id
      into l_rule_id
      from review_rule
      where rule_code = in_rule_code and is_active = 'Y';
      select
         rule_version_id
         , version_no
         , min_delinquency_status
      into l_rule_version_id, l_version_no, l_min_status
      from review_rule_version
      where rule_id = l_rule_id and effective_from <= in_reporting_month
      order by effective_from desc, version_no desc
      fetch first 1 row only;

      -- A misspelled release or a month outside the data must fail, not publish an empty delivery
      select count(*)
      into l_month_rows
      from loan_dw.dwd_loan_monthly_perf
      where
         release_id = in_release_id
         and monthly_reporting_period = in_reporting_month
         and rownum = 1;
      if l_month_rows = 0 then
         raise_application_error(-20602, 'The warehouse has no rows for this release and reporting month');
      end if;

      delete from review_evidence_month_stage;
      delete from review_evidence_stage;
      delete from review_candidate_stage;

      -- 1. Candidates: this month at or above the threshold, last month below it (a missing last month counts as current)
      insert into review_candidate_stage (
         rule_version_id
         , data_source
         , loan_identifier
         , reporting_month
         , delinquency_status
         , source_release_id
      )
      with

      two_months as (
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

      select
         l_rule_version_id
         , t.data_source
         , t.loan_identifier
         , t.monthly_reporting_period
         , t.current_loan_delinquency_status
         , in_release_id
      from two_months t
      left join two_months p
         on
            t.data_source = p.data_source
            and t.loan_identifier = p.loan_identifier
            and p.monthly_reporting_period = add_months(in_reporting_month, -1)
      where
         t.monthly_reporting_period = in_reporting_month
         and t.dlq_level >= l_min_status
         and coalesce(p.dlq_level, 0) < l_min_status;

      -- 2. Monthly history: only months that exist, from 12 months before the reporting month to the reporting month
      insert into review_evidence_month_stage (
         rule_version_id
         , data_source
         , loan_identifier
         , reporting_month
         , monthly_reporting_period
         , current_loan_delinquency_status
         , current_actual_upb
         , current_interest_rate
         , zero_balance_code
         , zero_balance_effective_date
         , modification_flag
      )
      select
         c.rule_version_id
         , c.data_source
         , c.loan_identifier
         , c.reporting_month
         , p.monthly_reporting_period
         , p.current_loan_delinquency_status
         , p.current_actual_upb
         , p.current_interest_rate
         , p.zero_balance_code
         , p.zero_balance_effective_date
         , p.modification_flag
      from review_candidate_stage c
      inner join loan_dw.dwd_loan_monthly_perf p
         on
            p.release_id = c.source_release_id
            and p.data_source = c.data_source
            and p.loan_identifier = c.loan_identifier
            and p.monthly_reporting_period
            between add_months(c.reporting_month, -12) and c.reporting_month;

      -- 3. Evidence: origination fields, the reporting month, last month, and the list of missing months
      insert into review_evidence_stage (
         rule_version_id
         , data_source
         , loan_identifier
         , reporting_month
         , source_release_id
         , rule_code
         , version_no
         , min_delinquency_status
         , classic_fico
         , original_upb
         , original_loan_to_value_ltv
         , original_interest_rate
         , property_state
         , origination_year
         , first_payment_date
         , current_loan_delinquency_status
         , current_actual_upb
         , current_interest_rate
         , zero_balance_code
         , zero_balance_effective_date
         , modification_flag
         , previous_delinquency_status
         , previous_month_missing
         , missing_months
      )
      with

      expected as (
         select add_months(in_reporting_month, -(level - 1)) as month_start
         from dual
         connect by level <= 13
      )

      , missing as (
         select
            c.data_source
            , c.loan_identifier
            , listagg(to_char(e.month_start, 'YYYY-MM-DD'), '|')
               within group (order by e.month_start) as missing_months
         from review_candidate_stage c
         cross join expected e
         where not exists (
            select 1
            from review_evidence_month_stage m
            where
               m.data_source = c.data_source
               and m.loan_identifier = c.loan_identifier
               and m.monthly_reporting_period = e.month_start
         )
         group by c.data_source, c.loan_identifier
      )

      select
         c.rule_version_id
         , c.data_source
         , c.loan_identifier
         , c.reporting_month
         , c.source_release_id
         , in_rule_code
         , l_version_no
         , l_min_status
         , d.classic_fico
         , d.original_upb
         , d.original_loan_to_value_ltv
         , d.original_interest_rate
         , d.property_state
         , d.origination_year
         , d.first_payment_date
         , cur.current_loan_delinquency_status
         , cur.current_actual_upb
         , cur.current_interest_rate
         , cur.zero_balance_code
         , cur.zero_balance_effective_date
         , cur.modification_flag
         , prv.current_loan_delinquency_status
         , case when prv.loan_identifier is null then 'true' else 'false' end
         , ms.missing_months
      from review_candidate_stage c
      inner join loan_dw.dim_loan d
         on
            d.release_id = c.source_release_id
            and d.data_source = c.data_source
            and d.loan_identifier = c.loan_identifier
      inner join review_evidence_month_stage cur
         on
            cur.data_source = c.data_source
            and cur.loan_identifier = c.loan_identifier
            and cur.monthly_reporting_period = c.reporting_month
      left join review_evidence_month_stage prv
         on
            prv.data_source = c.data_source
            and prv.loan_identifier = c.loan_identifier
            and prv.monthly_reporting_period = add_months(c.reporting_month, -1)
      left join missing ms
         on
            ms.data_source = c.data_source
            and ms.loan_identifier = c.loan_identifier;

      seal(in_release_id, in_reporting_month, l_rule_version_id, out_manifest);
   end stage_month;

   procedure seal(
      in_release_id in varchar2
      , in_reporting_month in date
      , in_rule_version_id in number
      , out_manifest out varchar2
   ) is
      c_num constant varchar2(30) := 'FM999999999999990.000';
      l_candidates pls_integer;
      l_evidence pls_integer;
      l_months pls_integer;
      l_years varchar2(400);
      l_chain varchar2(4000) := '';
      l_digest varchar2(64);
      l_rule review_rule.rule_code%type;
      l_version_no review_rule_version.version_no%type;
      l_min_status review_rule_version.min_delinquency_status%type;
      l_effective review_rule_version.effective_from%type;
   begin
      update review_evidence_stage e
      set
         content_sha256 = (
            select
               lower(rawtohex(standard_hash(
                  to_char(e.rule_version_id, c_num)
                  || '|' || e.data_source
                  || '|' || e.loan_identifier
                  || '|' || to_char(e.reporting_month, 'YYYY-MM-DD')
                  || '|' || e.source_release_id
                  || '|' || e.rule_code
                  || '|' || to_char(e.version_no, c_num)
                  || '|' || to_char(e.min_delinquency_status, c_num)
                  || '|' || to_char(e.classic_fico, c_num)
                  || '|' || to_char(e.original_upb, c_num)
                  || '|' || to_char(e.original_loan_to_value_ltv, c_num)
                  || '|' || to_char(e.original_interest_rate, c_num)
                  || '|' || e.property_state
                  || '|' || to_char(e.origination_year, c_num)
                  || '|' || to_char(e.first_payment_date, 'YYYY-MM-DD')
                  || '|' || e.current_loan_delinquency_status
                  || '|' || to_char(e.current_actual_upb, c_num)
                  || '|' || to_char(e.current_interest_rate, c_num)
                  || '|' || e.zero_balance_code
                  || '|' || to_char(e.zero_balance_effective_date, 'YYYY-MM-DD')
                  || '|' || e.modification_flag
                  || '|' || e.previous_delinquency_status
                  || '|' || e.previous_month_missing
                  || '|' || e.missing_months
                  || '#'
                  || listagg(
                     to_char(m.monthly_reporting_period, 'YYYY-MM-DD')
                     || '|' || m.current_loan_delinquency_status
                     || '|' || to_char(m.current_actual_upb, c_num)
                     || '|' || to_char(m.current_interest_rate, c_num)
                     || '|' || m.zero_balance_code
                     || '|' || to_char(m.zero_balance_effective_date, 'YYYY-MM-DD')
                     || '|' || m.modification_flag
                     , ';'
                  ) within group (order by m.monthly_reporting_period)
                  , 'SHA256'
               )))
            from review_evidence_month_stage m
            where
               m.rule_version_id = e.rule_version_id
               and m.data_source = e.data_source
               and m.loan_identifier = e.loan_identifier
               and m.reporting_month = e.reporting_month
         );

      select count(*) into l_candidates from review_candidate_stage;
      select count(*), listagg(distinct to_char(origination_year), ',') within group (order by to_char(origination_year))
      into l_evidence, l_years
      from review_evidence_stage;
      select count(*) into l_months from review_evidence_month_stage;

      -- Content digest of the whole delivery: chain the evidence digests in business-key order
      for r in (
         select content_sha256
         from review_evidence_stage
         order by data_source, loan_identifier, reporting_month, rule_version_id
      ) loop
         l_chain := l_chain || r.content_sha256;
         if length(l_chain) > 3800 then
            select lower(rawtohex(standard_hash(l_chain, 'SHA256'))) into l_chain from dual;
         end if;
      end loop;
      select lower(rawtohex(standard_hash(l_chain || '#', 'SHA256'))) into l_digest from dual;

      select
         r.rule_code
         , v.version_no
         , v.min_delinquency_status
         , v.effective_from
      into l_rule, l_version_no, l_min_status, l_effective
      from review_rule_version v
      inner join review_rule r
         on v.rule_id = r.rule_id
      where v.rule_version_id = in_rule_version_id;

      select json_object(
         'schema_version' value 3
         , 'product' value 'REVIEW_CANDIDATES'
         , 'release' value in_release_id
         , 'reporting_month' value to_char(in_reporting_month, 'YYYY-MM-DD')
         , 'source_years' value '[' || l_years || ']' format json
         , 'rule' value json_object(
            'rule_code' value l_rule
            , 'rule_version_id' value in_rule_version_id
            , 'version_no' value l_version_no
            , 'min_delinquency_status' value l_min_status
            , 'effective_from' value to_char(l_effective, 'YYYY-MM-DD')
         )
         , 'rows' value json_object(
            'review_candidate' value l_candidates
            , 'review_evidence' value l_evidence
            , 'review_evidence_month' value l_months
         )
         , 'content_sha256' value l_digest
         returning varchar2(4000)
      )
      into out_manifest
      from dual;
   end seal;

end candidate_publish;
/
