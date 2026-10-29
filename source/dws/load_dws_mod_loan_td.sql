-- load_dws_mod_loan_td.sql
-- Load dws mod loan td. See docs/metric_definitions.md for analytical definitions.
create or replace procedure load_dws_mod_loan_td(
   in_release_id in varchar2
   , in_only_listed in varchar2 default 'N'
) is
   l_modified pls_integer;
   l_release_rows pls_integer;
begin
   delete from dws_mod_loan_td
   where
      release_id = in_release_id
      and (
         in_only_listed = 'N'
         or loan_identifier in (
            select loan_identifier
            from dw_recompute_loan
            where release_id = in_release_id
         )
      );

   insert into dws_mod_loan_td (
      loan_identifier
      , origination_year
      , first_mod_period
      , mod_count
      , is_dlq60_before_mod
      , first_redefault_period
      , state_12m
      , release_id
   )
   with

   scope_listed as (
      select loan_identifier
      from dw_recompute_loan
      where
         release_id = in_release_id
         and change_kind != 'REMOVED'
         and in_only_listed = 'Y'
   )

   , scope as (
      select loan_identifier
      from dim_loan
      where release_id = in_release_id and in_only_listed = 'N'
      union all
      select loan_identifier
      from scope_listed
   )

   , dwd as (
      select
         loan_identifier
         , monthly_reporting_period
         , current_loan_delinquency_status
         , zero_balance_code
         , modification_flag
         , data_source
         , release_id
      from dwd_loan_monthly_perf
      where release_id = in_release_id and in_only_listed = 'N'
      union all
      select
         w.loan_identifier
         , w.monthly_reporting_period
         , w.current_loan_delinquency_status
         , w.zero_balance_code
         , w.modification_flag
         , w.data_source
         , w.release_id
      from dwd_loan_monthly_perf w
      inner join scope_listed sl
         on w.loan_identifier = sl.loan_identifier
      where w.release_id = in_release_id  -- noqa: RF02,RF03
   )

   , dim as (
      select
         loan_identifier
         , origination_year
      from dim_loan
      where
         release_id = in_release_id
         and loan_identifier in (select sc.loan_identifier from scope sc)
   )

   , states as (
      select /*+ use_hash(s z) */
         w.loan_identifier
         , w.monthly_reporting_period
         , w.modification_flag
         , w.release_id
         , s.is_dlq60
         , z.exit_state
         , coalesce(z.exit_state, s.dlq_state) as cur_state
      from dwd w
      left join dim_delinquency_status s
         on w.current_loan_delinquency_status = s.status_code
      left join dim_zero_balance_code z
         on
            w.data_source = z.data_source
            and w.zero_balance_code = z.zero_balance_code
   )

   , mods as (
      select
         loan_identifier
         , min(monthly_reporting_period) as first_mod_period
         , count(*) as mod_count
      from states
      where modification_flag = 'Y'
      group by loan_identifier
   )

   , mod_rows as (
      select
         m.loan_identifier
         , m.first_mod_period
         , m.mod_count
         , t.monthly_reporting_period
         , t.release_id
         , t.is_dlq60
         , t.exit_state
         , t.cur_state
         , months_between(t.monthly_reporting_period, m.first_mod_period)
            as months_after_mod
      from mods m
      inner join states t
         on m.loan_identifier = t.loan_identifier
   )

   , by_loan as (
      select
         loan_identifier
         , first_mod_period
         , mod_count
         , max(release_id) as release_id
         , max(
            case when months_after_mod between -12 and -1 then is_dlq60 end
         ) as is_dlq60_before_mod
         , min(
            case
               when is_dlq60 = 'Y' and months_after_mod between 1 and 12
                  then monthly_reporting_period
            end
         ) as first_redefault_period
         , max(
            case when months_after_mod = 12 then cur_state end
         ) as state_at_12m
         , max(monthly_reporting_period) as last_period
         , max(exit_state) as exit_state
      from mod_rows
      group by loan_identifier, first_mod_period, mod_count
   )

   select
      b.loan_identifier
      , d.origination_year
      , b.first_mod_period
      , b.mod_count
      , b.is_dlq60_before_mod
      , b.first_redefault_period
      , case
         when b.state_at_12m is not null then b.state_at_12m
         when
            b.exit_state is not null
            and b.last_period < add_months(b.first_mod_period, 12)
            then b.exit_state
      end as state_12m
      , b.release_id
   from by_loan b
   inner join dim d
      on b.loan_identifier = d.loan_identifier;

   select count(distinct loan_identifier)
   into l_modified
   from dwd_loan_monthly_perf
   where
      release_id = in_release_id
      and modification_flag = 'Y';
   select count(*)
   into l_release_rows
   from dws_mod_loan_td
   where release_id = in_release_id;
   if l_release_rows != l_modified then
      raise_application_error(
         -20001
         , 'dws_mod_loan_td row count mismatch: release ' || l_release_rows
         || ', modified loans ' || l_modified
      );
   end if;
end load_dws_mod_loan_td;
/
