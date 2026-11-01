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

-- DQ017 (internal rule): every column that is converted to a number must fit its official type;
-- otherwise the whole batch is rejected (each offending cell is logged; rows are not quarantined).
-- Why check before conversion: the detail columns are number(p,s), and Oracle silently rounds
-- extra decimal places on insert instead of raising an error.
-- Why reject the batch: a malformed or over-long value usually means the publisher changed the format;
-- quarantining a few rows would quietly shrink the analysis, so loading stops for a manual review.
-- Only the numeric value counts: integer digits after removing the sign and leading zeros, and
-- decimal digits after removing trailing zeros; anything that is not a plain number (letters,
-- spaces, exponents) also fails.
-- Official types come from both File Layouts (Numeric 4 = 4 integer digits; Numeric - 12,2 =
-- 12 digits in total, 2 of them decimals). Column 12 (non-interest bearing UPB) has no scale in
-- the File Layout; it is treated as 12,2 because the User Guide (July 2026) defines Current Actual
-- UPB as interest bearing plus non-interest bearing UPB (p.10) and lists it as a $ Amount (p.12).
insert into dq_issue (
   run_id, release_id, rule_id, source_table, source_file
   , loan_identifier, raw_period, reason, disposition
)
with
cells as (
   select
      'ODS_ORIG' as source_table, source_file, loan_identifier
      , cast(null as varchar2(20)) as raw_period, column_name, raw_value
   from (select * from ods_orig where release_id = '&release_id')
   unpivot (
      raw_value for column_name in (
         classic_fico as 'classic_fico'
         , mortgage_insurance_percentage_mi as 'mortgage_insurance_percentage_mi'
         , number_of_units as 'number_of_units'
         , original_combined_loan_to_value_cltv
         as 'original_combined_loan_to_value_cltv'
         , original_debt_to_income_dti_ratio
         as 'original_debt_to_income_dti_ratio'
         , original_upb as 'original_upb'
         , original_loan_to_value_ltv as 'original_loan_to_value_ltv'
         , original_interest_rate as 'original_interest_rate'
         , original_loan_term as 'original_loan_term'
         , number_of_borrowers as 'number_of_borrowers'
         , vantagescore_4_0 as 'vantagescore_4_0'
      )
   )
   union all
   select
      'ODS_ORIG_PRE202607', source_file, loan_sequence_number
      , cast(null as varchar2(20)), column_name, raw_value
   from (select * from ods_orig_pre202607 where release_id = '&release_id')
   unpivot (
      raw_value for column_name in (
         credit_score as 'credit_score'
         , mortgage_insurance_percentage_mi as 'mortgage_insurance_percentage_mi'
         , number_of_units as 'number_of_units'
         , original_combined_loan_to_value_cltv
         as 'original_combined_loan_to_value_cltv'
         , original_debt_to_income_dti_ratio
         as 'original_debt_to_income_dti_ratio'
         , original_upb as 'original_upb'
         , original_loan_to_value_ltv as 'original_loan_to_value_ltv'
         , original_interest_rate as 'original_interest_rate'
         , original_loan_term as 'original_loan_term'
         , number_of_borrowers as 'number_of_borrowers'
      )
   )
   union all
   select
      'ODS_PERF', source_file, loan_identifier
      , monthly_reporting_period, column_name, raw_value
   from (select * from ods_perf where release_id = '&release_id')
   unpivot (
      raw_value for column_name in (
         current_actual_upb as 'current_actual_upb'
         , loan_age as 'loan_age'
         , remaining_months_to_legal_maturity
         as 'remaining_months_to_legal_maturity'
         , current_interest_rate as 'current_interest_rate'
         , current_non_interest_bearing_upb as 'current_non_interest_bearing_upb'
         , mi_recoveries as 'mi_recoveries'
         , non_mi_recoveries as 'non_mi_recoveries'
         , total_expenses as 'total_expenses'
         , legal_costs as 'legal_costs'
         , maintenance_and_preservation_costs
         as 'maintenance_and_preservation_costs'
         , taxes_and_insurance as 'taxes_and_insurance'
         , miscellaneous_expenses as 'miscellaneous_expenses'
         , actual_loss as 'actual_loss'
         , cumulative_modification_costs as 'cumulative_modification_costs'
         , estimated_loan_to_value_eltv as 'estimated_loan_to_value_eltv'
         , zero_balance_removal_upb as 'zero_balance_removal_upb'
         , delinquent_accrued_interest as 'delinquent_accrued_interest'
         , current_period_modification_costs
         as 'current_period_modification_costs'
         , current_interest_bearing_upb as 'current_interest_bearing_upb'
         , bankruptcy_cramdown_costs as 'bankruptcy_cramdown_costs'
      )
   )
   union all
   select
      'ODS_PERF_PRE202607', source_file, loan_sequence_number
      , monthly_reporting_period, column_name, raw_value
   from (select * from ods_perf_pre202607 where release_id = '&release_id')
   unpivot (
      raw_value for column_name in (
         current_actual_upb as 'current_actual_upb'
         , loan_age as 'loan_age'
         , remaining_months_to_legal_maturity
         as 'remaining_months_to_legal_maturity'
         , current_interest_rate as 'current_interest_rate'
         , current_deferred_upb as 'current_deferred_upb'
         , mi_recoveries as 'mi_recoveries'
         , non_mi_recoveries as 'non_mi_recoveries'
         , expenses as 'expenses'
         , legal_costs as 'legal_costs'
         , maintenance_and_preservation_costs
         as 'maintenance_and_preservation_costs'
         , taxes_and_insurance as 'taxes_and_insurance'
         , miscellaneous_expenses as 'miscellaneous_expenses'
         , actual_loss_calculation as 'actual_loss_calculation'
         , modification_cost as 'modification_cost'
         , estimated_loan_to_value_eltv as 'estimated_loan_to_value_eltv'
         , zero_balance_removal_upb as 'zero_balance_removal_upb'
         , delinquent_accrued_interest as 'delinquent_accrued_interest'
         , current_month_modification_cost as 'current_month_modification_cost'
         , interest_bearing_upb as 'interest_bearing_upb'
      )
   )
)

-- Allowed integer and decimal digits per column; columns not listed are 12,2 amounts
-- (Numeric - 12,2 = 10 integer digits + 2 decimals)
, spec as (
   -- Origination file (same in both layouts; File Layout columns 1, 6, 7, 9-13, 22, 23, 31)
   select 'classic_fico' as column_name, 4 as int_digits, 0 as scale_digits from dual
   union all select 'credit_score', 4, 0 from dual
   union all select 'mortgage_insurance_percentage_mi', 3, 0 from dual
   union all select 'number_of_units', 2, 0 from dual
   union all select 'original_combined_loan_to_value_cltv', 3, 0 from dual
   union all select 'original_debt_to_income_dti_ratio', 3, 0 from dual
   union all select 'original_upb', 12, 0 from dual
   union all select 'original_loan_to_value_ltv', 3, 0 from dual
   union all select 'original_interest_rate', 3, 3 from dual
   union all select 'original_loan_term', 3, 0 from dual
   union all select 'number_of_borrowers', 2, 0 from dual
   union all select 'vantagescore_4_0', 4, 0 from dual
   -- Monthly performance file (same in both layouts; File Layout columns 5, 6, 11, 26)
   union all select 'loan_age', 3, 0 from dual
   union all select 'remaining_months_to_legal_maturity', 3, 0 from dual
   union all select 'current_interest_rate', 5, 3 from dual
   union all select 'estimated_loan_to_value_eltv', 4, 0 from dual
)

, checked as (
   select
      c.*
      , coalesce(s.int_digits, 10) as int_digits
      , coalesce(s.scale_digits, 2) as scale_digits
   from cells c
   left join spec s on s.column_name = c.column_name
)

select
   :dq_run_id, '&release_id', 'DQ017', source_table, source_file
   , loan_identifier, raw_period
   , substr('Number does not fit the official type: ' || column_name || '=' || raw_value, 1, 200)
   , 'REJECT'
from checked
where
   not regexp_like(raw_value, '^-?[0-9]*(\.[0-9]*)?$')
   or not regexp_like(raw_value, '[0-9]')
   or coalesce(
      length(ltrim(regexp_substr(raw_value, '^-?([0-9]*)', 1, 1, null, 1), '0'))
      , 0
   ) > int_digits
   or coalesce(
      length(rtrim(regexp_substr(raw_value, '\.([0-9]*)$', 1, 1, null, 1), '0'))
      , 0
   ) > scale_digits;

insert into dq_check_result (
   run_id, rule_id, severity, rule_desc, bad_count, release_id, dw_layer
)
select
   :dq_run_id
   , 'DQ017'
   , 'HARD'
   , 'Cells whose number does not fit the official type or is not a number (whole batch rejected)'
   , count(*)
   , '&release_id'
   , 'ODS'
from dq_issue
where run_id = :dq_run_id and rule_id = 'DQ017';

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
