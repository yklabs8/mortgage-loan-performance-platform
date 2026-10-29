-- load_dwd_loan_monthly_perf.sql
-- Require a fresh successful ODS gate. Quarantined rows remain in ODS and are excluded here. Normalize earlier-layout dates, delinquency codes, cash-flow signs and servicer names using Disclosure Changes v1.2. Reconcile inserted plus quarantined rows against source counts.
create or replace procedure load_dwd_loan_monthly_perf(
   in_release_id in varchar2
) is
   l_ods_rows pls_integer;
   l_ods_new pls_integer;
   l_ods_old pls_integer;
   l_quarantined pls_integer;
   l_dq_run_id number;
   l_bad_net_sales pls_integer;
   l_inserted pls_integer;
begin
   select max(run_id)
   into l_dq_run_id
   from dq_ods_ready_run
   where release_id = in_release_id;
   if l_dq_run_id is null then
      raise_application_error(-20001, 'No successful dq_ods run: ' || in_release_id);
   end if;
   select count(*)
   into l_bad_net_sales
   from ods_perf_pre202607
   where
      release_id = in_release_id
      and regexp_like(net_sales_proceeds, '^-?[0-9]*\.[0-9]{3,}$');
   if l_bad_net_sales > 0 then
      raise_application_error(
         -20001
         , 'Old-layout net sales proceeds exceed two decimal places: ' || in_release_id
         || ', count ' || l_bad_net_sales || ' rows'
      );
   end if;

   insert into dwd_loan_monthly_perf_stage (
      loan_identifier
      , monthly_reporting_period
      , current_actual_upb
      , current_loan_delinquency_status
      , loan_age
      , remaining_months_to_legal_maturity
      , defect_settlement_date
      , modification_flag
      , zero_balance_code
      , zero_balance_effective_date
      , current_interest_rate
      , current_non_interest_bearing_upb
      , due_date_of_last_paid_installment_ddlpi
      , mi_recoveries
      , net_sales_proceeds
      , non_mi_recoveries
      , total_expenses
      , legal_costs
      , maintenance_and_preservation_costs
      , taxes_and_insurance
      , miscellaneous_expenses
      , actual_loss
      , cumulative_modification_costs
      , interest_rate_step_indicator
      , payment_deferral_flag
      , estimated_loan_to_value_eltv
      , zero_balance_removal_upb
      , delinquent_accrued_interest
      , delinquency_due_to_disaster
      , borrower_assistance_plan
      , current_period_modification_costs
      , current_interest_bearing_upb
      , mortgage_insurance_cancellation_indicator
      , servicer_name
      , bankruptcy_cramdown_costs
      , data_source
      , release_id
      , loan_key
      , period_date_key
      , servicer_key
   )
   select
      loan_identifier
      , to_date(monthly_reporting_period, 'YYYYMM') as monthly_reporting_period
      , to_number(current_actual_upb) as current_actual_upb
      , current_loan_delinquency_status
      , to_number(loan_age) as loan_age
      , to_number(
         remaining_months_to_legal_maturity
      ) as remaining_months_to_legal_maturity
      , to_date(
         underwriting_defect_and_major_servicing_defect_settlement_date
         , 'YYYYMM'
      ) as defect_settlement_date
      , modification_flag
      , zero_balance_code
      , to_date(
         zero_balance_effective_date
         , 'YYYYMM'
      ) as zero_balance_effective_date
      , to_number(current_interest_rate) as current_interest_rate
      , to_number(
         current_non_interest_bearing_upb
      ) as current_non_interest_bearing_upb
      , to_date(
         due_date_of_last_paid_installment_ddlpi
         , 'YYYYMM'
      ) as due_date_of_last_paid_installment_ddlpi
      , to_number(mi_recoveries) as mi_recoveries
      , net_sales_proceeds
      , to_number(non_mi_recoveries) as non_mi_recoveries
      , to_number(total_expenses) as total_expenses
      , to_number(legal_costs) as legal_costs
      , to_number(
         maintenance_and_preservation_costs
      ) as maintenance_and_preservation_costs
      , to_number(taxes_and_insurance) as taxes_and_insurance
      , to_number(miscellaneous_expenses) as miscellaneous_expenses
      , to_number(actual_loss) as actual_loss
      , to_number(
         cumulative_modification_costs
      ) as cumulative_modification_costs
      , interest_rate_step_indicator
      , payment_deferral_flag
      , to_number(estimated_loan_to_value_eltv) as estimated_loan_to_value_eltv
      , to_number(zero_balance_removal_upb) as zero_balance_removal_upb
      , to_number(delinquent_accrued_interest) as delinquent_accrued_interest
      , delinquency_due_to_disaster
      , borrower_assistance_plan
      , to_number(
         current_period_modification_costs
      ) as current_period_modification_costs
      , to_number(current_interest_bearing_upb) as current_interest_bearing_upb
      , mortgage_insurance_cancellation_indicator
      , servicer_name
      , to_number(bankruptcy_cramdown_costs) as bankruptcy_cramdown_costs
      , 'FRE' as data_source
      , release_id
      , (
         select dl.loan_key
         from dim_loan dl
         where
            dl.release_id = ods_perf.release_id
            and dl.loan_identifier = ods_perf.loan_identifier
      ) as loan_key
      , to_number(
         to_char(to_date(monthly_reporting_period, 'YYYYMM'), 'YYYYMMDD')
      ) as period_date_key
      , case
         when servicer_name is null then 0
         else (
            select ds.servicer_key
            from dim_servicer ds
            where ds.servicer_name = ods_perf.servicer_name
         )
      end as servicer_key
   from ods_perf
   where
      release_id = in_release_id
      and not exists (
         select 1 from dq_ods_quarantine_keys q
         where
            q.release_id = ods_perf.release_id
            and q.source_table = 'ODS_PERF'
            and q.source_file = ods_perf.source_file
            and q.loan_identifier = ods_perf.loan_identifier
            and q.raw_period = ods_perf.monthly_reporting_period
      );
   l_inserted := sql%rowcount;

   insert into dwd_loan_monthly_perf_stage (
      loan_identifier
      , monthly_reporting_period
      , current_actual_upb
      , current_loan_delinquency_status
      , loan_age
      , remaining_months_to_legal_maturity
      , defect_settlement_date
      , modification_flag
      , zero_balance_code
      , zero_balance_effective_date
      , current_interest_rate
      , current_non_interest_bearing_upb
      , due_date_of_last_paid_installment_ddlpi
      , mi_recoveries
      , net_sales_proceeds
      , non_mi_recoveries
      , total_expenses
      , legal_costs
      , maintenance_and_preservation_costs
      , taxes_and_insurance
      , miscellaneous_expenses
      , actual_loss
      , cumulative_modification_costs
      , interest_rate_step_indicator
      , payment_deferral_flag
      , estimated_loan_to_value_eltv
      , zero_balance_removal_upb
      , delinquent_accrued_interest
      , delinquency_due_to_disaster
      , borrower_assistance_plan
      , current_period_modification_costs
      , current_interest_bearing_upb
      , mortgage_insurance_cancellation_indicator
      , servicer_name
      , bankruptcy_cramdown_costs
      , data_source
      , release_id
      , loan_key
      , period_date_key
      , servicer_key
   )
   with old_orig as (
      select
         loan_sequence_number
         , mortgage_insurance_cancellation_indicator
         , case
            when upper(servicer_name) = 'OTHER SERVICERS' then 'OTHER'
            else servicer_name
         end as servicer_name
         , release_id
      from ods_orig_pre202607
      where release_id = in_release_id
   )

   select
      o.loan_sequence_number as loan_identifier
      , to_date(
         o.monthly_reporting_period
         , 'YYYYMM'
      ) as monthly_reporting_period
      , to_number(o.current_actual_upb) as current_actual_upb
      , case
         when regexp_like(o.current_loan_delinquency_status, '^[0-9]+$')
            then
               lpad(
                  least(to_number(o.current_loan_delinquency_status), 99)
                  , 2
                  , '0'
               )
         else o.current_loan_delinquency_status
      end as current_loan_delinquency_status
      , to_number(o.loan_age) as loan_age
      , to_number(
         o.remaining_months_to_legal_maturity
      ) as remaining_months_to_legal_maturity
      , to_date(
         o.defect_settlement_date
         , 'YYYYMM'
      ) as defect_settlement_date
      , o.modification_flag
      , o.zero_balance_code
      , to_date(
         o.zero_balance_effective_date
         , 'YYYYMM'
      ) as zero_balance_effective_date
      , to_number(o.current_interest_rate) as current_interest_rate
      , to_number(o.current_deferred_upb) as current_non_interest_bearing_upb
      , to_date(
         o.due_date_of_last_paid_installment_ddlpi
         , 'YYYYMM'
      ) as due_date_of_last_paid_installment_ddlpi
      , -to_number(o.mi_recoveries) as mi_recoveries
      , case
         when regexp_like(o.net_sales_proceeds, '^-?[0-9.]+$')
            then to_char(-to_number(o.net_sales_proceeds), 'FM9999999999990.00')
         else o.net_sales_proceeds
      end as net_sales_proceeds
      , -to_number(o.non_mi_recoveries) as non_mi_recoveries
      , -to_number(o.expenses) as total_expenses
      , -to_number(o.legal_costs) as legal_costs
      , -to_number(
         o.maintenance_and_preservation_costs
      ) as maintenance_and_preservation_costs
      , -to_number(o.taxes_and_insurance) as taxes_and_insurance
      , -to_number(o.miscellaneous_expenses) as miscellaneous_expenses
      , -to_number(o.actual_loss_calculation) as actual_loss
      , to_number(o.modification_cost) as cumulative_modification_costs
      , o.step_modification_flag as interest_rate_step_indicator
      , case
         when o.deferred_payment_plan = 'Y' then 'C'
         else o.deferred_payment_plan
      end as payment_deferral_flag
      , coalesce(
         to_number(o.estimated_loan_to_value_eltv), 999
      ) as estimated_loan_to_value_eltv
      , to_number(o.zero_balance_removal_upb) as zero_balance_removal_upb
      , to_number(o.delinquent_accrued_interest) as delinquent_accrued_interest
      , o.delinquency_due_to_disaster
      , o.borrower_assistance_status_code as borrower_assistance_plan
      , to_number(
         o.current_month_modification_cost
      ) as current_period_modification_costs
      , to_number(o.interest_bearing_upb) as current_interest_bearing_upb
      , case
         when g.mortgage_insurance_cancellation_indicator = '9' then '7'
         else g.mortgage_insurance_cancellation_indicator
      end as mortgage_insurance_cancellation_indicator
      , g.servicer_name
      , null as bankruptcy_cramdown_costs
      , 'FRE' as data_source
      , o.release_id
      , (
         select dl.loan_key
         from dim_loan dl
         where
            dl.release_id = o.release_id
            and dl.loan_identifier = o.loan_sequence_number
      ) as loan_key
      , to_number(
         to_char(to_date(o.monthly_reporting_period, 'YYYYMM'), 'YYYYMMDD')
      ) as period_date_key
      , case
         when g.servicer_name is null then 0
         else (
            select ds.servicer_key
            from dim_servicer ds
            where ds.servicer_name = g.servicer_name
         )
      end as servicer_key
   from ods_perf_pre202607 o
   inner join old_orig g
      on
         o.release_id = g.release_id
         and o.loan_sequence_number = g.loan_sequence_number
   where
      not exists (
         select 1 from dq_ods_quarantine_keys q
         where
            q.release_id = o.release_id
            and q.source_table = 'ODS_PERF_PRE202607'
            and q.source_file = o.source_file
            and q.loan_identifier = o.loan_sequence_number
            and q.raw_period = o.monthly_reporting_period
      );
   l_inserted := l_inserted + sql%rowcount;


   select count(*)
   into l_ods_new
   from ods_perf
   where release_id = in_release_id;
   select count(*)
   into l_ods_old
   from ods_perf_pre202607
   where release_id = in_release_id;
   select count(*)
   into l_quarantined
   from dq_ods_quarantine_keys
   where release_id = in_release_id;
   l_ods_rows := l_ods_new + l_ods_old;
   if l_inserted = 0 or l_inserted + l_quarantined != l_ods_rows then
      raise_application_error(
         -20001
         , 'dwd_loan_monthly_perf_stage row count mismatch: inserted ' || l_inserted
         || ', quarantined ' || l_quarantined || ', ODS ' || l_ods_rows
      );
   end if;
end load_dwd_loan_monthly_perf;
/
