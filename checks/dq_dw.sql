-- dq_dw.sql
-- Check unique detail grain, source/detail/quarantine counts, UPB totals, summary counts, transition totals, and cumulative-rate bounds. Retain every run. HARD failures stop; WARN results remain recorded.
-- noqa: disable=all
variable dq_run_id number
-- noqa: enable=all

begin
   insert into dq_run (release_id, check_scope)
   values ('&release_id', 'DW')
   returning run_id into :dq_run_id;
end;
/

insert into dq_check_result (
   run_id, rule_id, severity, rule_desc, bad_count, release_id, dw_layer
)
with

this_run as (
   select :dq_run_id as run_id
   from dual
)

, dwd as (
   select
      loan_identifier
      , monthly_reporting_period
      , current_actual_upb
      , servicer_key
      , modification_flag
   from dwd_loan_monthly_perf
   where release_id = '&release_id'
)

, dwd_total as (
   select
      count(*) as row_count_
      , sum(current_actual_upb) as upb_sum
      , count(
         distinct loan_identifier || '|'
         || to_char(monthly_reporting_period, 'yyyymmdd')
      ) as distinct_loan_months
      , count(
         distinct case when modification_flag = 'Y' then loan_identifier end
      ) as modified_loans
      , count(case when servicer_key = 0 then 1 end) as no_servicer_rows
      , count(case when current_actual_upb is null then 1 end) as null_upb_rows
   from dwd
)

, ods_parts as (
   select
      count(*) as row_count_
      , sum(case when not exists (
         select 1 from dq_ods_quarantine_keys q
         where q.release_id = ods_perf.release_id
            and q.source_table = 'ODS_PERF'
            and q.source_file = ods_perf.source_file
            and q.loan_identifier = ods_perf.loan_identifier
            and q.raw_period = ods_perf.monthly_reporting_period
      ) then to_number(current_actual_upb) end) as upb_sum
   from ods_perf
   where release_id = '&release_id'
   union all
   select
      count(*) as row_count_
      , sum(case when not exists (
         select 1 from dq_ods_quarantine_keys q
         where q.release_id = ods_perf_pre202607.release_id
            and q.source_table = 'ODS_PERF_PRE202607'
            and q.source_file = ods_perf_pre202607.source_file
            and q.loan_identifier = ods_perf_pre202607.loan_sequence_number
            and q.raw_period = ods_perf_pre202607.monthly_reporting_period
      ) then to_number(current_actual_upb) end) as upb_sum
   from ods_perf_pre202607
   where release_id = '&release_id'

)

, quarantine_total as (
   select count(*) as row_count_
   from dq_ods_quarantine_keys
   where release_id = '&release_id'
)

, ods_total as (
   select
      sum(row_count_) as row_count_
      , sum(upb_sum) as upb_sum
   from ods_parts
)

, dwd_gap as (
   select
      months_between(
         monthly_reporting_period
         , lag(monthly_reporting_period) over (
            partition by loan_identifier order by monthly_reporting_period
         )
      ) as gap_months
   from dwd
)

, gap_total as (
   select count(*) as transition_rows
   from dwd_gap
   where gap_months = 1
)

, loans as (
   select count(*) as loan_count
   from dim_loan
   where release_id = '&release_id'
)

, dws_perf as (
   select
      count(*) as row_count_
      , sum(months_reported) as months_sum
      , count(case when months_reported = 0 then 1 end) as no_record_loans
   from dws_perf_loan_td
   where release_id = '&release_id'
)

, dws_mod as (
   select count(*) as row_count_
   from dws_mod_loan_td
   where release_id = '&release_id'
)

, transitions as (
   select sum(loan_count) as loan_count_sum
   from ads_dlq_transition_monthly
   where release_id = '&release_id'
)

, vintage_curve as (
   select count(*) as row_count_
   from ads_vintage_dlq60_curve
   where release_id = '&release_id'
)

, mod_outcomes as (
   select coalesce(sum(modified_loans), 0) as modified_loans
   from ads_modification_outcome
   where release_id = '&release_id'
)

, results as (
   select
      'DQ013' as rule_id
      , 'HARD' as severity
      , 'DWD' as dw_layer
      , 'Duplicate fact loan/reporting-month rows' as rule_desc
      , row_count_ - distinct_loan_months as bad_count
   from dwd_total
   union all
   select
      'DQ014A' as rule_id
      , 'HARD' as severity
      , 'DWD' as dw_layer
      , 'ODS count differs from fact plus quarantined rows; 1 on mismatch' as rule_desc
      , case when d.row_count_ + q.row_count_ = o.row_count_
         then 0 else 1 end as bad_count
   from dwd_total d
   cross join ods_total o
   cross join quarantine_total q
   union all
   select
      'DQ014B' as rule_id
      , 'HARD' as severity
      , 'DWD' as dw_layer
      , 'Fact current UPB total differs from ODS; 1 on mismatch' as rule_desc
      , decode(d.upb_sum, o.upb_sum, 0, 1) as bad_count
   from dwd_total d
   cross join ods_total o
   union all
   select
      'DWD002' as rule_id
      , 'WARN' as severity
      , 'DWD' as dw_layer
      , 'Rows without a disclosed servicer name (servicer_key = 0)' as rule_desc
      , no_servicer_rows as bad_count
   from dwd_total
   union all
   select
      'DWD003' as rule_id
      , 'WARN' as severity
      , 'DWD' as dw_layer
      , 'Rows with NULL current UPB' as rule_desc
      , null_upb_rows as bad_count
   from dwd_total
   union all
   select
      'DWS001' as rule_id
      , 'HARD' as severity
      , 'DWS' as dw_layer
      , 'dws_perf_loan_td count differs from dim_loan count; 1 on mismatch' as rule_desc
      , case when p.row_count_ = l.loan_count then 0 else 1 end as bad_count
   from dws_perf p
   cross join loans l
   union all
   select
      'DWS002' as rule_id
      , 'HARD' as severity
      , 'DWS' as dw_layer
      , 'Sum of DWS month counts differs from fact count; 1 on mismatch' as rule_desc
      , case when p.months_sum = d.row_count_ then 0 else 1 end as bad_count
   from dws_perf p
   cross join dwd_total d
   union all
   select
      'DWS003' as rule_id
      , 'HARD' as severity
      , 'DWS' as dw_layer
      , 'dws_mod_loan_td count differs from modified-loan count; 1 on mismatch' as rule_desc
      , case when m.row_count_ = d.modified_loans then 0 else 1 end as bad_count
   from dws_mod m
   cross join dwd_total d
   union all
   select
      'DWS004' as rule_id
      , 'WARN' as severity
      , 'DWS' as dw_layer
      , 'Loans without monthly records' as rule_desc
      , no_record_loans as bad_count
   from dws_perf
   union all
   select
      'ADS000A' as rule_id
      , 'HARD' as severity
      , 'ADS' as dw_layer
      , 'Cumulative 60+ curve is empty; 1 if empty' as rule_desc
      , case when row_count_ = 0 then 1 else 0 end as bad_count
   from vintage_curve
   union all
   select
      'ADS000B' as rule_id
      , 'HARD' as severity
      , 'ADS' as dw_layer
      , 'Modification outcome count differs from modification summary count; 1 on mismatch' as rule_desc
      , case when a.modified_loans = d.row_count_ then 0 else 1 end as bad_count
   from mod_outcomes a
   cross join dws_mod d
   union all
   select
      'ADS001' as rule_id
      , 'HARD' as severity
      , 'ADS' as dw_layer
      , 'Transition total differs from adjacent-month transitions in facts; 1 on mismatch' as rule_desc
      , case
         when coalesce(t.loan_count_sum, 0) = g.transition_rows then 0 else 1
      end as bad_count
   from transitions t
   cross join gap_total g
   union all
   select
      'ADS002' as rule_id
      , 'HARD' as severity
      , 'ADS' as dw_layer
      , 'Cumulative 60+ curve rows with invalid counts, bounds, or rates' as rule_desc
      , count(*) as bad_count
   from ads_vintage_dlq60_curve
   where
      release_id = '&release_id'
      and (
         cum_dlq60_loans < 0
         or eligible_loans <= 0
         or cohort_loans <= 0
         or cum_dlq60_loans > eligible_loans
         or eligible_loans > cohort_loans
         or case
            when eligible_loans > 0
               and cum_dlq60_rate != cum_dlq60_loans / eligible_loans
               then 1
            else 0
         end = 1
      )
)

select
   tr.run_id
   , rs.rule_id
   , rs.severity
   , rs.rule_desc
   , rs.bad_count
   , '&release_id' as release_id
   , rs.dw_layer
from results rs
cross join this_run tr;

commit;

select
   dw_layer
   , rule_id
   , severity
   , bad_count
   , rule_desc
from dq_check_result
where run_id = :dq_run_id
order by dw_layer asc, rule_id asc;

declare
   l_hard_failed pls_integer;
begin
   select count(*)
   into l_hard_failed
   from dq_check_result
   where
      run_id = :dq_run_id
      and severity = 'HARD'
      and bad_count > 0;
   if l_hard_failed > 0 then
      raise_application_error(
         -20001, l_hard_failed || ' HARD rules failed; see dq_check_result'
      );
   end if;
end;
/
