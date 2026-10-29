-- compare_dwd_loan_monthly_perf.sql
-- Compare dwd loan monthly perf. See docs/metric_definitions.md for analytical definitions.
create or replace procedure compare_dwd_loan_monthly_perf(
   in_old_release_id in varchar2
   , in_new_release_id in varchar2
) is
begin
   insert into ads_release_diff_summary (
      old_release_id
      , new_release_id
      , source_table
      , source_column
      , change_type
      , affected_rows
   )
   with

   old_rows as (
      select
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
      from dwd_loan_monthly_perf
      where
         release_id = in_old_release_id
         and loan_identifier in (
            select l.loan_identifier
            from dim_loan l
            where
               l.release_id = in_old_release_id  -- noqa: RF02,RF03
               and l.origination_year in (
                  select y.origination_year
                  from dim_loan y
                  where y.release_id = in_new_release_id  -- noqa: RF02,RF03
               )
         )
   )

   , new_rows as (
      select
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
      from dwd_loan_monthly_perf
      where
         release_id = in_new_release_id
         and loan_identifier in (
            select l.loan_identifier
            from dim_loan l
            where
               l.release_id = in_new_release_id  -- noqa: RF02,RF03
               and l.origination_year in (
                  select y.origination_year
                  from dim_loan y
                  where y.release_id = in_old_release_id  -- noqa: RF02,RF03
               )
         )
   )

   , flags as (
      select
         sum(decode(o.current_actual_upb, n.current_actual_upb, 0, 1)) as c1
         , sum(decode(
            o.current_loan_delinquency_status
            , n.current_loan_delinquency_status
            , 0
            , 1
         )) as c2
         , sum(decode(o.loan_age, n.loan_age, 0, 1)) as c3
         , sum(decode(
            o.remaining_months_to_legal_maturity
            , n.remaining_months_to_legal_maturity
            , 0
            , 1
         )) as c4
         , sum(decode(
            o.defect_settlement_date
            , n.defect_settlement_date
            , 0
            , 1
         )) as c5
         , sum(decode(o.modification_flag, n.modification_flag, 0, 1)) as c6
         , sum(decode(o.zero_balance_code, n.zero_balance_code, 0, 1)) as c7
         , sum(decode(
            o.zero_balance_effective_date
            , n.zero_balance_effective_date
            , 0
            , 1
         )) as c8
         , sum(decode(
            o.current_interest_rate
            , n.current_interest_rate
            , 0
            , 1
         )) as c9
         , sum(decode(
            o.current_non_interest_bearing_upb
            , n.current_non_interest_bearing_upb
            , 0
            , 1
         )) as c10
         , sum(decode(
            o.due_date_of_last_paid_installment_ddlpi
            , n.due_date_of_last_paid_installment_ddlpi
            , 0
            , 1
         )) as c11
         , sum(decode(o.mi_recoveries, n.mi_recoveries, 0, 1)) as c12
         , sum(decode(o.net_sales_proceeds, n.net_sales_proceeds, 0, 1)) as c13
         , sum(decode(o.non_mi_recoveries, n.non_mi_recoveries, 0, 1)) as c14
         , sum(decode(o.total_expenses, n.total_expenses, 0, 1)) as c15
         , sum(decode(o.legal_costs, n.legal_costs, 0, 1)) as c16
         , sum(decode(
            o.maintenance_and_preservation_costs
            , n.maintenance_and_preservation_costs
            , 0
            , 1
         )) as c17
         , sum(decode(
            o.taxes_and_insurance
            , n.taxes_and_insurance
            , 0
            , 1
         )) as c18
         , sum(decode(
            o.miscellaneous_expenses
            , n.miscellaneous_expenses
            , 0
            , 1
         )) as c19
         , sum(decode(o.actual_loss, n.actual_loss, 0, 1)) as c20
         , sum(decode(
            o.cumulative_modification_costs
            , n.cumulative_modification_costs
            , 0
            , 1
         )) as c21
         , sum(decode(
            o.interest_rate_step_indicator
            , n.interest_rate_step_indicator
            , 0
            , 1
         )) as c22
         , sum(decode(
            o.payment_deferral_flag
            , n.payment_deferral_flag
            , 0
            , 1
         )) as c23
         , sum(decode(
            o.estimated_loan_to_value_eltv
            , n.estimated_loan_to_value_eltv
            , 0
            , 1
         )) as c24
         , sum(decode(
            o.zero_balance_removal_upb
            , n.zero_balance_removal_upb
            , 0
            , 1
         )) as c25
         , sum(decode(
            o.delinquent_accrued_interest
            , n.delinquent_accrued_interest
            , 0
            , 1
         )) as c26
         , sum(decode(
            o.delinquency_due_to_disaster
            , n.delinquency_due_to_disaster
            , 0
            , 1
         )) as c27
         , sum(decode(
            o.borrower_assistance_plan
            , n.borrower_assistance_plan
            , 0
            , 1
         )) as c28
         , sum(decode(
            o.current_period_modification_costs
            , n.current_period_modification_costs
            , 0
            , 1
         )) as c29
         , sum(decode(
            o.current_interest_bearing_upb
            , n.current_interest_bearing_upb
            , 0
            , 1
         )) as c30
         , sum(decode(
            o.mortgage_insurance_cancellation_indicator
            , n.mortgage_insurance_cancellation_indicator
            , 0
            , 1
         )) as c31
         , sum(decode(o.servicer_name, n.servicer_name, 0, 1)) as c32
         , sum(decode(
            o.bankruptcy_cramdown_costs
            , n.bankruptcy_cramdown_costs
            , 0
            , 1
         )) as c33
      from old_rows o
      inner join new_rows n
         on
            o.loan_identifier = n.loan_identifier
            and o.monthly_reporting_period = n.monthly_reporting_period
   )

   select
      in_old_release_id as old_release_id
      , in_new_release_id as new_release_id
      , 'dwd_loan_monthly_perf' as source_table
      , lower(source_column) as source_column
      , 'VALUE_CHANGED' as change_type
      , affected_rows
   from flags
   unpivot (affected_rows for source_column in (
      c1 as 'current_actual_upb'
      , c2 as 'current_loan_delinquency_status'
      , c3 as 'loan_age'
      , c4 as 'remaining_months_to_legal_maturity'
      , c5 as 'defect_settlement_date'
      , c6 as 'modification_flag'
      , c7 as 'zero_balance_code'
      , c8 as 'zero_balance_effective_date'
      , c9 as 'current_interest_rate'
      , c10 as 'current_non_interest_bearing_upb'
      , c11 as 'due_date_of_last_paid_installment_ddlpi'
      , c12 as 'mi_recoveries'
      , c13 as 'net_sales_proceeds'
      , c14 as 'non_mi_recoveries'
      , c15 as 'total_expenses'
      , c16 as 'legal_costs'
      , c17 as 'maintenance_and_preservation_costs'
      , c18 as 'taxes_and_insurance'
      , c19 as 'miscellaneous_expenses'
      , c20 as 'actual_loss'
      , c21 as 'cumulative_modification_costs'
      , c22 as 'interest_rate_step_indicator'
      , c23 as 'payment_deferral_flag'
      , c24 as 'estimated_loan_to_value_eltv'
      , c25 as 'zero_balance_removal_upb'
      , c26 as 'delinquent_accrued_interest'
      , c27 as 'delinquency_due_to_disaster'
      , c28 as 'borrower_assistance_plan'
      , c29 as 'current_period_modification_costs'
      , c30 as 'current_interest_bearing_upb'
      , c31 as 'mortgage_insurance_cancellation_indicator'
      , c32 as 'servicer_name'
      , c33 as 'bankruptcy_cramdown_costs'
   ));

   insert into ads_release_diff_summary (
      old_release_id
      , new_release_id
      , source_table
      , source_column
      , change_type
      , affected_rows
   )
   with

   old_keys as (
      select
         loan_identifier
         , monthly_reporting_period
      from dwd_loan_monthly_perf
      where
         release_id = in_old_release_id
         and loan_identifier in (
            select l.loan_identifier
            from dim_loan l
            where
               l.release_id = in_old_release_id  -- noqa: RF02,RF03
               and l.origination_year in (
                  select y.origination_year
                  from dim_loan y
                  where y.release_id = in_new_release_id  -- noqa: RF02,RF03
               )
         )
   )

   , new_keys as (
      select
         loan_identifier
         , monthly_reporting_period
      from dwd_loan_monthly_perf
      where
         release_id = in_new_release_id
         and loan_identifier in (
            select l.loan_identifier
            from dim_loan l
            where
               l.release_id = in_new_release_id  -- noqa: RF02,RF03
               and l.origination_year in (
                  select y.origination_year
                  from dim_loan y
                  where y.release_id = in_old_release_id  -- noqa: RF02,RF03
               )
         )
   )

   , old_last as (
      select max(ok.monthly_reporting_period) as last_period
      from old_keys ok
   )

   , sides as (
      select 'OLD_ONLY' as change_type
      from old_keys o
      where
         not exists (
            select 1 from new_keys n
            where
               o.loan_identifier = n.loan_identifier
               and o.monthly_reporting_period = n.monthly_reporting_period
         )
      union all
      select
         case
            when n.monthly_reporting_period <= l.last_period
               then 'NEW_ONLY_WITHIN_OLD_RANGE'
            else 'NEW_MONTHS'
         end as change_type
      from new_keys n
      cross join old_last l
      where not exists (
         select 1 from old_keys o
         where
            o.loan_identifier = n.loan_identifier
            and o.monthly_reporting_period = n.monthly_reporting_period
      )
   )

   select
      in_old_release_id as old_release_id
      , in_new_release_id as new_release_id
      , 'dwd_loan_monthly_perf' as source_table
      , '(whole row)' as source_column
      , change_type
      , count(*) as affected_rows
   from sides
   group by change_type;

   insert into ads_release_diff_detail (
      old_release_id
      , new_release_id
      , source_table
      , loan_identifier
      , monthly_reporting_period
      , source_column
      , old_value
      , new_value
   )
   with

   old_rows as (
      select
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
      from dwd_loan_monthly_perf
      where
         release_id = in_old_release_id
         and loan_identifier in (
            select l.loan_identifier
            from dim_loan l
            where
               l.release_id = in_old_release_id  -- noqa: RF02,RF03
               and l.origination_year in (
                  select y.origination_year
                  from dim_loan y
                  where y.release_id = in_new_release_id  -- noqa: RF02,RF03
               )
         )
   )

   , new_rows as (
      select
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
      from dwd_loan_monthly_perf
      where
         release_id = in_new_release_id
         and loan_identifier in (
            select l.loan_identifier
            from dim_loan l
            where
               l.release_id = in_new_release_id  -- noqa: RF02,RF03
               and l.origination_year in (
                  select y.origination_year
                  from dim_loan y
                  where y.release_id = in_old_release_id  -- noqa: RF02,RF03
               )
         )
   )

   , pairs as (
      select
         o.loan_identifier
         , o.monthly_reporting_period
         , to_char(o.current_actual_upb) as o1
         , to_char(n.current_actual_upb) as n1
         , to_char(o.current_loan_delinquency_status) as o2
         , to_char(n.current_loan_delinquency_status) as n2
         , to_char(o.loan_age) as o3
         , to_char(n.loan_age) as n3
         , to_char(o.remaining_months_to_legal_maturity) as o4
         , to_char(n.remaining_months_to_legal_maturity) as n4
         , to_char(o.defect_settlement_date) as o5
         , to_char(n.defect_settlement_date) as n5
         , to_char(o.modification_flag) as o6
         , to_char(n.modification_flag) as n6
         , to_char(o.zero_balance_code) as o7
         , to_char(n.zero_balance_code) as n7
         , to_char(o.zero_balance_effective_date) as o8
         , to_char(n.zero_balance_effective_date) as n8
         , to_char(o.current_interest_rate) as o9
         , to_char(n.current_interest_rate) as n9
         , to_char(o.current_non_interest_bearing_upb) as o10
         , to_char(n.current_non_interest_bearing_upb) as n10
         , to_char(o.due_date_of_last_paid_installment_ddlpi) as o11
         , to_char(n.due_date_of_last_paid_installment_ddlpi) as n11
         , to_char(o.mi_recoveries) as o12
         , to_char(n.mi_recoveries) as n12
         , to_char(o.net_sales_proceeds) as o13
         , to_char(n.net_sales_proceeds) as n13
         , to_char(o.non_mi_recoveries) as o14
         , to_char(n.non_mi_recoveries) as n14
         , to_char(o.total_expenses) as o15
         , to_char(n.total_expenses) as n15
         , to_char(o.legal_costs) as o16
         , to_char(n.legal_costs) as n16
         , to_char(o.maintenance_and_preservation_costs) as o17
         , to_char(n.maintenance_and_preservation_costs) as n17
         , to_char(o.taxes_and_insurance) as o18
         , to_char(n.taxes_and_insurance) as n18
         , to_char(o.miscellaneous_expenses) as o19
         , to_char(n.miscellaneous_expenses) as n19
         , to_char(o.actual_loss) as o20
         , to_char(n.actual_loss) as n20
         , to_char(o.interest_rate_step_indicator) as o21
         , to_char(n.interest_rate_step_indicator) as n21
         , to_char(o.payment_deferral_flag) as o22
         , to_char(n.payment_deferral_flag) as n22
         , to_char(o.zero_balance_removal_upb) as o23
         , to_char(n.zero_balance_removal_upb) as n23
         , to_char(o.delinquent_accrued_interest) as o24
         , to_char(n.delinquent_accrued_interest) as n24
         , to_char(o.delinquency_due_to_disaster) as o25
         , to_char(n.delinquency_due_to_disaster) as n25
         , to_char(o.borrower_assistance_plan) as o26
         , to_char(n.borrower_assistance_plan) as n26
         , to_char(o.current_period_modification_costs) as o27
         , to_char(n.current_period_modification_costs) as n27
         , to_char(o.current_interest_bearing_upb) as o28
         , to_char(n.current_interest_bearing_upb) as n28
      from old_rows o
      inner join new_rows n
         on
            o.loan_identifier = n.loan_identifier
            and o.monthly_reporting_period = n.monthly_reporting_period
   )

   select
      in_old_release_id as old_release_id
      , in_new_release_id as new_release_id
      , 'dwd_loan_monthly_perf' as source_table
      , loan_identifier
      , monthly_reporting_period
      , lower(source_column) as source_column
      , old_value
      , new_value
   from pairs
   unpivot ((old_value, new_value) for source_column in (
      (o1, n1) as 'current_actual_upb'
      , (o2, n2) as 'current_loan_delinquency_status'
      , (o3, n3) as 'loan_age'
      , (o4, n4) as 'remaining_months_to_legal_maturity'
      , (o5, n5) as 'defect_settlement_date'
      , (o6, n6) as 'modification_flag'
      , (o7, n7) as 'zero_balance_code'
      , (o8, n8) as 'zero_balance_effective_date'
      , (o9, n9) as 'current_interest_rate'
      , (o10, n10) as 'current_non_interest_bearing_upb'
      , (o11, n11) as 'due_date_of_last_paid_installment_ddlpi'
      , (o12, n12) as 'mi_recoveries'
      , (o13, n13) as 'net_sales_proceeds'
      , (o14, n14) as 'non_mi_recoveries'
      , (o15, n15) as 'total_expenses'
      , (o16, n16) as 'legal_costs'
      , (o17, n17) as 'maintenance_and_preservation_costs'
      , (o18, n18) as 'taxes_and_insurance'
      , (o19, n19) as 'miscellaneous_expenses'
      , (o20, n20) as 'actual_loss'
      , (o21, n21) as 'interest_rate_step_indicator'
      , (o22, n22) as 'payment_deferral_flag'
      , (o23, n23) as 'zero_balance_removal_upb'
      , (o24, n24) as 'delinquent_accrued_interest'
      , (o25, n25) as 'delinquency_due_to_disaster'
      , (o26, n26) as 'borrower_assistance_plan'
      , (o27, n27) as 'current_period_modification_costs'
      , (o28, n28) as 'current_interest_bearing_upb'
   ))
   where decode(old_value, new_value, 0, 1) = 1;
end compare_dwd_loan_monthly_perf;
/
