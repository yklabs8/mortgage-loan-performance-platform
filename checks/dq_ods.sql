-- dq_ods.sql
-- Record each rule result and each offending source row. HARD failures stop the run. DQ004/DQ006 may continue only when every invalid row has been quarantined. Reconcile issue and quarantine counts before marking the run ready. Never delete source rows.
-- noqa: disable=all
variable dq_run_id number
-- noqa: enable=all

begin
   insert into dq_run (release_id, check_scope)
   values ('&release_id', 'ODS')
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

, orig as (
   select loan_identifier
   from ods_orig
   where release_id = '&release_id'
   union all
   select loan_sequence_number as loan_identifier
   from ods_orig_pre202607
   where release_id = '&release_id'
)

, perf as (
   select
      'FRE' as data_source
      , loan_identifier
      , monthly_reporting_period
      , zero_balance_code
      , zero_balance_effective_date
   from ods_perf
   where release_id = '&release_id'
   union all
   select
      'FRE' as data_source
      , loan_sequence_number as loan_identifier
      , monthly_reporting_period
      , zero_balance_code
      , zero_balance_effective_date
   from ods_perf_pre202607
   where release_id = '&release_id'
)

, perf_seq as (
   select
      monthly_reporting_period
      , min(
         case
            when zero_balance_code is not null then monthly_reporting_period
         end
      ) over (partition by loan_identifier) as end_period
      , lag(monthly_reporting_period) over (
         partition by loan_identifier order by monthly_reporting_period
      ) as prev_period
   from perf
)

, results as (
   select
      'DQ000' as rule_id
      , 'HARD' as severity
      , 'Release has both origination and performance rows; 1 if either is empty' as rule_desc
      , case
         when
            (select count(*) from orig) = 0 or (select count(*) from perf) = 0
            then 1
         else 0
      end as bad_count
   from dual
   union all
   select
      'DQ003' as rule_id
      , 'HARD' as severity
      , 'Duplicate origination loan IDs' as rule_desc
      , count(*) - count(distinct loan_identifier) as bad_count
   from orig
   union all
   select
      'DQ004' as rule_id
      , 'HARD' as severity
      , 'Performance loans missing from originations' as rule_desc
      , count(distinct p.loan_identifier) as bad_count
   from perf p
   where
      not exists (
         select 1 from orig o
         where o.loan_identifier = p.loan_identifier
      )
   union all
   select
      'DQ004B' as rule_id
      , 'WARN' as severity
      , 'Origination loans without monthly records' as rule_desc
      , count(*) as bad_count
   from orig o
   where
      not exists (
         select 1 from perf p
         where p.loan_identifier = o.loan_identifier
      )
   union all
   select
      'DQ005' as rule_id
      , 'HARD' as severity
      , 'Duplicate loan/reporting-month performance rows' as rule_desc
      , count(*)
      - count(distinct loan_identifier || '|' || monthly_reporting_period)
         as bad_count
   from perf
   union all
   select
      'DQ006' as rule_id
      , 'HARD' as severity
      , 'Performance months that are not valid YYYYMM' as rule_desc
      , count(*) as bad_count
   from perf
   where
      not regexp_like(monthly_reporting_period, '^[0-9]{4}(0[1-9]|1[0-2])$')
      or substr(monthly_reporting_period, 1, 4) = '0000'
   union all
   select
      'DQ007A' as rule_id
      , 'HARD' as severity
      , 'Zero-balance codes outside the official agency list in dim_zero_balance_code'
         as rule_desc
      , count(*) as bad_count
   from perf p
   where
      p.zero_balance_code is not null
      and not exists (
         select 1 from dim_zero_balance_code z
         where
            z.data_source = p.data_source
            and z.zero_balance_code = p.zero_balance_code
      )
   union all
   select
      'DQ007B' as rule_id
      , 'WARN' as severity
      , 'Rows with exactly one of exit code and exit date populated' as rule_desc
      , count(*) as bad_count
   from perf
   where
      (zero_balance_code is null and zero_balance_effective_date is not null)
      or (zero_balance_code is not null and zero_balance_effective_date is null)
   union all
   select
      'DQ008' as rule_id
      , 'WARN' as severity
      , 'Records after the exit month' as rule_desc
      , count(*) as bad_count
   from perf_seq
   where monthly_reporting_period > end_period
   union all
   select
      'DQ009' as rule_id
      , 'WARN' as severity
      , 'Gaps exceeding one month between consecutive records' as rule_desc
      , count(*) as bad_count
   from perf_seq
   where
      months_between(
         case
            when regexp_like(monthly_reporting_period, '^[0-9]{4}(0[1-9]|1[0-2])$')
               and substr(monthly_reporting_period, 1, 4) != '0000'
               then to_date(monthly_reporting_period, 'YYYYMM')
         end
         , case
            when regexp_like(prev_period, '^[0-9]{4}(0[1-9]|1[0-2])$')
               and substr(prev_period, 1, 4) != '0000'
               then to_date(prev_period, 'YYYYMM')
         end
      ) > 1
)

select
   tr.run_id
   , rs.rule_id
   , rs.severity
   , rs.rule_desc
   , rs.bad_count
   , '&release_id' as release_id
   , 'ODS' as dw_layer
from results rs
cross join this_run tr;

insert into dq_issue (
   run_id, release_id, rule_id, source_table, source_file
   , loan_identifier, raw_period, reason, disposition
)
with
orig as (
   select 'ODS_ORIG' as source_table, source_file, loan_identifier
   from ods_orig where release_id = '&release_id'
   union all
   select 'ODS_ORIG_PRE202607', source_file, loan_sequence_number
   from ods_orig_pre202607 where release_id = '&release_id'
)
, perf as (
   select 'ODS_PERF' as source_table, source_file, loan_identifier
      , monthly_reporting_period as raw_period
      , monthly_reporting_period as period_yyyymm
      , zero_balance_code, zero_balance_effective_date
      , 'FRE' as data_source
   from ods_perf where release_id = '&release_id'
   union all
   select 'ODS_PERF_PRE202607', source_file, loan_sequence_number
      , monthly_reporting_period, monthly_reporting_period
      , zero_balance_code, zero_balance_effective_date, 'FRE'
   from ods_perf_pre202607 where release_id = '&release_id'
)
, numbered_orig as (
   select o.*
      , row_number() over (partition by loan_identifier order by source_file) as rn
   from orig o
)
, numbered_perf as (
   select p.*
      , row_number() over (
         partition by loan_identifier, raw_period order by source_file
      ) as rn
      , min(case when zero_balance_code is not null then period_yyyymm end)
         over (partition by loan_identifier) as end_period
      , lag(period_yyyymm) over (
         partition by loan_identifier order by period_yyyymm
      ) as prev_period
   from perf p
)
, findings as (
   select 'DQ000' as rule_id, 'ODS' as source_table
      , cast(null as varchar2(100)) as source_file
      , cast(null as varchar2(50)) as loan_identifier
      , cast(null as varchar2(20)) as raw_period
      , 'Empty origination or performance data' as reason, 'REJECT' as disposition
   from dual
   where (select count(*) from orig) = 0 or (select count(*) from perf) = 0
   union all
   select 'DQ003', source_table, source_file, loan_identifier, null
      , 'Duplicate origination loan ID', 'REJECT'
   from numbered_orig where rn > 1
   union all
   select 'DQ004', p.source_table, p.source_file, p.loan_identifier, p.raw_period
      , 'Monthly record without origination', 'QUARANTINE'
   from perf p
   where not exists (
      select 1 from orig o where o.loan_identifier = p.loan_identifier
   )
   union all
   select 'DQ004B', o.source_table, o.source_file, o.loan_identifier, null
      , 'Origination without monthly records', 'WARN'
   from orig o
   where not exists (
      select 1 from perf p where p.loan_identifier = o.loan_identifier
   )
   union all
   select 'DQ005', source_table, source_file, loan_identifier, raw_period
      , 'Duplicate loan and reporting month', 'REJECT'
   from numbered_perf where rn > 1
   union all
   select 'DQ006', source_table, source_file, loan_identifier, raw_period
      , 'Invalid reporting month', 'QUARANTINE'
   from perf
   where not regexp_like(period_yyyymm, '^[0-9]{4}(0[1-9]|1[0-2])$')
      or substr(period_yyyymm, 1, 4) = '0000'
   union all
   select 'DQ007A', p.source_table, p.source_file, p.loan_identifier, p.raw_period
      , 'Exit code outside the official agency list', 'REJECT'
   from perf p
   where p.zero_balance_code is not null
      and not exists (
         select 1 from dim_zero_balance_code z
         where z.data_source = p.data_source
            and z.zero_balance_code = p.zero_balance_code
      )
   union all
   select 'DQ007B', source_table, source_file, loan_identifier, raw_period
      , 'Only one of exit code and date populated', 'WARN'
   from perf
   where (zero_balance_code is null and zero_balance_effective_date is not null)
      or (zero_balance_code is not null and zero_balance_effective_date is null)
   union all
   select 'DQ008', source_table, source_file, loan_identifier, raw_period
      , 'Record after exit month', 'WARN'
   from numbered_perf where period_yyyymm > end_period
   union all
   select 'DQ009', source_table, source_file, loan_identifier, raw_period
      , 'Gap greater than one month', 'WARN'
   from numbered_perf
   where months_between(
      case when regexp_like(period_yyyymm, '^[0-9]{4}(0[1-9]|1[0-2])$')
         and substr(period_yyyymm, 1, 4) != '0000'
         then to_date(period_yyyymm, 'YYYYMM') end
      , case when regexp_like(prev_period, '^[0-9]{4}(0[1-9]|1[0-2])$')
         and substr(prev_period, 1, 4) != '0000'
         then to_date(prev_period, 'YYYYMM') end
   ) > 1
)
select :dq_run_id, '&release_id', rule_id, source_table, source_file
   , loan_identifier, raw_period, reason, disposition
from findings;

insert into dq_quarantine (
   issue_id, release_id, source_table, source_file, loan_identifier
   , raw_period, rule_id, reason
)
select issue_id, release_id, source_table, source_file, loan_identifier
   , raw_period, rule_id, reason
from dq_issue
where run_id = :dq_run_id and disposition = 'QUARANTINE';

commit;

select
   rule_id
   , severity
   , bad_count
   , rule_desc
from dq_check_result
where run_id = :dq_run_id
order by rule_id;

declare
   l_hard_failed pls_integer;
begin
   select count(*)
   into l_hard_failed
   from dq_check_result c
   where
      run_id = :dq_run_id
      and severity = 'HARD'
      and bad_count > 0
      and (
         rule_id not in ('DQ004', 'DQ006')
         or bad_count != (
            select case
               when c.rule_id = 'DQ004' then count(distinct q.loan_identifier)
               else count(*)
            end
            from dq_quarantine q
            inner join dq_issue i on i.issue_id = q.issue_id
            where i.run_id = :dq_run_id and q.rule_id = c.rule_id
         )
      );
   if l_hard_failed > 0 then
      raise_application_error(
         -20001, l_hard_failed || ' HARD rules failed; see dq_check_result'
      );
   end if;
end;
/
