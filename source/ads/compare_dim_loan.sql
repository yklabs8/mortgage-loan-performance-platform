-- compare_dim_loan.sql
-- Compare dim loan. See docs/metric_definitions.md for analytical definitions.
create or replace procedure compare_dim_loan(
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
         , classic_fico
         , first_payment_date
         , first_time_homebuyer_indicator
         , maturity_date
         , msa_code
         , mortgage_insurance_percentage_mi
         , number_of_units
         , occupancy_status
         , original_combined_loan_to_value_cltv
         , original_debt_to_income_dti_ratio
         , original_upb
         , original_loan_to_value_ltv
         , original_interest_rate
         , channel
         , prepayment_penalty_indicator
         , amortization_type
         , property_state
         , property_type
         , postal_code
         , loan_purpose
         , original_loan_term
         , number_of_borrowers
         , seller_name
         , super_conforming_flag
         , pre_harp_loan_sequence_number
         , special_eligibility_program
         , harp_indicator
         , property_valuation_method
         , interest_only_i_o_indicator
         , vantagescore_4_0
         , origination_year
         , origination_quarter
      from dim_loan
      where
         release_id = in_old_release_id
         and origination_year in (
            select y.origination_year
            from dim_loan y
            where y.release_id = in_new_release_id  -- noqa: RF02,RF03
         )
   )

   , new_rows as (
      select
         loan_identifier
         , classic_fico
         , first_payment_date
         , first_time_homebuyer_indicator
         , maturity_date
         , msa_code
         , mortgage_insurance_percentage_mi
         , number_of_units
         , occupancy_status
         , original_combined_loan_to_value_cltv
         , original_debt_to_income_dti_ratio
         , original_upb
         , original_loan_to_value_ltv
         , original_interest_rate
         , channel
         , prepayment_penalty_indicator
         , amortization_type
         , property_state
         , property_type
         , postal_code
         , loan_purpose
         , original_loan_term
         , number_of_borrowers
         , seller_name
         , super_conforming_flag
         , pre_harp_loan_sequence_number
         , special_eligibility_program
         , harp_indicator
         , property_valuation_method
         , interest_only_i_o_indicator
         , vantagescore_4_0
         , origination_year
         , origination_quarter
      from dim_loan
      where
         release_id = in_new_release_id
         and origination_year in (
            select y.origination_year
            from dim_loan y
            where y.release_id = in_old_release_id  -- noqa: RF02,RF03
         )
   )

   , flags as (
      select
         sum(decode(o.classic_fico, n.classic_fico, 0, 1)) as c1
         , sum(decode(o.first_payment_date, n.first_payment_date, 0, 1)) as c2
         , sum(decode(
            o.first_time_homebuyer_indicator
            , n.first_time_homebuyer_indicator
            , 0
            , 1
         )) as c3
         , sum(decode(o.maturity_date, n.maturity_date, 0, 1)) as c4
         , sum(decode(o.msa_code, n.msa_code, 0, 1)) as c5
         , sum(decode(
            o.mortgage_insurance_percentage_mi
            , n.mortgage_insurance_percentage_mi
            , 0
            , 1
         )) as c6
         , sum(decode(o.number_of_units, n.number_of_units, 0, 1)) as c7
         , sum(decode(o.occupancy_status, n.occupancy_status, 0, 1)) as c8
         , sum(decode(
            o.original_combined_loan_to_value_cltv
            , n.original_combined_loan_to_value_cltv
            , 0
            , 1
         )) as c9
         , sum(decode(
            o.original_debt_to_income_dti_ratio
            , n.original_debt_to_income_dti_ratio
            , 0
            , 1
         )) as c10
         , sum(decode(o.original_upb, n.original_upb, 0, 1)) as c11
         , sum(decode(
            o.original_loan_to_value_ltv
            , n.original_loan_to_value_ltv
            , 0
            , 1
         )) as c12
         , sum(decode(
            o.original_interest_rate
            , n.original_interest_rate
            , 0
            , 1
         )) as c13
         , sum(decode(o.channel, n.channel, 0, 1)) as c14
         , sum(decode(
            o.prepayment_penalty_indicator
            , n.prepayment_penalty_indicator
            , 0
            , 1
         )) as c15
         , sum(decode(o.amortization_type, n.amortization_type, 0, 1)) as c16
         , sum(decode(o.property_state, n.property_state, 0, 1)) as c17
         , sum(decode(o.property_type, n.property_type, 0, 1)) as c18
         , sum(decode(o.postal_code, n.postal_code, 0, 1)) as c19
         , sum(decode(o.loan_purpose, n.loan_purpose, 0, 1)) as c20
         , sum(decode(o.original_loan_term, n.original_loan_term, 0, 1)) as c21
         , sum(decode(
            o.number_of_borrowers
            , n.number_of_borrowers
            , 0
            , 1
         )) as c22
         , sum(decode(o.seller_name, n.seller_name, 0, 1)) as c23
         , sum(decode(
            o.super_conforming_flag
            , n.super_conforming_flag
            , 0
            , 1
         )) as c24
         , sum(decode(
            o.pre_harp_loan_sequence_number
            , n.pre_harp_loan_sequence_number
            , 0
            , 1
         )) as c25
         , sum(decode(
            o.special_eligibility_program
            , n.special_eligibility_program
            , 0
            , 1
         )) as c26
         , sum(decode(o.harp_indicator, n.harp_indicator, 0, 1)) as c27
         , sum(decode(
            o.property_valuation_method
            , n.property_valuation_method
            , 0
            , 1
         )) as c28
         , sum(decode(
            o.interest_only_i_o_indicator
            , n.interest_only_i_o_indicator
            , 0
            , 1
         )) as c29
         , sum(decode(o.vantagescore_4_0, n.vantagescore_4_0, 0, 1)) as c30
         , sum(decode(o.origination_year, n.origination_year, 0, 1)) as c31
         , sum(decode(
            o.origination_quarter
            , n.origination_quarter
            , 0
            , 1
         )) as c32
      from old_rows o
      inner join new_rows n
         on
            o.loan_identifier = n.loan_identifier
   )

   select
      in_old_release_id as old_release_id
      , in_new_release_id as new_release_id
      , 'dim_loan' as source_table
      , lower(source_column) as source_column
      , 'VALUE_CHANGED' as change_type
      , affected_rows
   from flags
   unpivot (affected_rows for source_column in (
      c1 as 'classic_fico'
      , c2 as 'first_payment_date'
      , c3 as 'first_time_homebuyer_indicator'
      , c4 as 'maturity_date'
      , c5 as 'msa_code'
      , c6 as 'mortgage_insurance_percentage_mi'
      , c7 as 'number_of_units'
      , c8 as 'occupancy_status'
      , c9 as 'original_combined_loan_to_value_cltv'
      , c10 as 'original_debt_to_income_dti_ratio'
      , c11 as 'original_upb'
      , c12 as 'original_loan_to_value_ltv'
      , c13 as 'original_interest_rate'
      , c14 as 'channel'
      , c15 as 'prepayment_penalty_indicator'
      , c16 as 'amortization_type'
      , c17 as 'property_state'
      , c18 as 'property_type'
      , c19 as 'postal_code'
      , c20 as 'loan_purpose'
      , c21 as 'original_loan_term'
      , c22 as 'number_of_borrowers'
      , c23 as 'seller_name'
      , c24 as 'super_conforming_flag'
      , c25 as 'pre_harp_loan_sequence_number'
      , c26 as 'special_eligibility_program'
      , c27 as 'harp_indicator'
      , c28 as 'property_valuation_method'
      , c29 as 'interest_only_i_o_indicator'
      , c30 as 'vantagescore_4_0'
      , c31 as 'origination_year'
      , c32 as 'origination_quarter'
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
      select loan_identifier
      from dim_loan
      where
         release_id = in_old_release_id
         and origination_year in (
            select y.origination_year
            from dim_loan y
            where y.release_id = in_new_release_id  -- noqa: RF02,RF03
         )
   )

   , new_keys as (
      select loan_identifier
      from dim_loan
      where
         release_id = in_new_release_id
         and origination_year in (
            select y.origination_year
            from dim_loan y
            where y.release_id = in_old_release_id  -- noqa: RF02,RF03
         )
   )

   , sides as (
      select 'OLD_ONLY' as change_type
      from old_keys o
      where
         not exists (
            select 1 from new_keys n
            where
               o.loan_identifier = n.loan_identifier
         )
      union all
      select 'NEW_ONLY' as change_type
      from new_keys n
      where not exists (
         select 1 from old_keys o
         where
            o.loan_identifier = n.loan_identifier
      )
   )

   select
      in_old_release_id as old_release_id
      , in_new_release_id as new_release_id
      , 'dim_loan' as source_table
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
         , classic_fico
         , first_payment_date
         , first_time_homebuyer_indicator
         , maturity_date
         , msa_code
         , mortgage_insurance_percentage_mi
         , number_of_units
         , occupancy_status
         , original_combined_loan_to_value_cltv
         , original_debt_to_income_dti_ratio
         , original_upb
         , original_loan_to_value_ltv
         , original_interest_rate
         , channel
         , prepayment_penalty_indicator
         , amortization_type
         , property_state
         , property_type
         , postal_code
         , loan_purpose
         , original_loan_term
         , number_of_borrowers
         , seller_name
         , super_conforming_flag
         , pre_harp_loan_sequence_number
         , special_eligibility_program
         , harp_indicator
         , property_valuation_method
         , interest_only_i_o_indicator
         , vantagescore_4_0
         , origination_year
         , origination_quarter
      from dim_loan
      where
         release_id = in_old_release_id
         and origination_year in (
            select y.origination_year
            from dim_loan y
            where y.release_id = in_new_release_id  -- noqa: RF02,RF03
         )
   )

   , new_rows as (
      select
         loan_identifier
         , classic_fico
         , first_payment_date
         , first_time_homebuyer_indicator
         , maturity_date
         , msa_code
         , mortgage_insurance_percentage_mi
         , number_of_units
         , occupancy_status
         , original_combined_loan_to_value_cltv
         , original_debt_to_income_dti_ratio
         , original_upb
         , original_loan_to_value_ltv
         , original_interest_rate
         , channel
         , prepayment_penalty_indicator
         , amortization_type
         , property_state
         , property_type
         , postal_code
         , loan_purpose
         , original_loan_term
         , number_of_borrowers
         , seller_name
         , super_conforming_flag
         , pre_harp_loan_sequence_number
         , special_eligibility_program
         , harp_indicator
         , property_valuation_method
         , interest_only_i_o_indicator
         , vantagescore_4_0
         , origination_year
         , origination_quarter
      from dim_loan
      where
         release_id = in_new_release_id
         and origination_year in (
            select y.origination_year
            from dim_loan y
            where y.release_id = in_old_release_id  -- noqa: RF02,RF03
         )
   )

   , pairs as (
      select
         o.loan_identifier
         , cast(null as date) as monthly_reporting_period
         , to_char(o.classic_fico) as o1
         , to_char(n.classic_fico) as n1
         , to_char(o.first_payment_date) as o2
         , to_char(n.first_payment_date) as n2
         , to_char(o.first_time_homebuyer_indicator) as o3
         , to_char(n.first_time_homebuyer_indicator) as n3
         , to_char(o.maturity_date) as o4
         , to_char(n.maturity_date) as n4
         , to_char(o.msa_code) as o5
         , to_char(n.msa_code) as n5
         , to_char(o.mortgage_insurance_percentage_mi) as o6
         , to_char(n.mortgage_insurance_percentage_mi) as n6
         , to_char(o.number_of_units) as o7
         , to_char(n.number_of_units) as n7
         , to_char(o.occupancy_status) as o8
         , to_char(n.occupancy_status) as n8
         , to_char(o.original_combined_loan_to_value_cltv) as o9
         , to_char(n.original_combined_loan_to_value_cltv) as n9
         , to_char(o.original_debt_to_income_dti_ratio) as o10
         , to_char(n.original_debt_to_income_dti_ratio) as n10
         , to_char(o.original_upb) as o11
         , to_char(n.original_upb) as n11
         , to_char(o.original_loan_to_value_ltv) as o12
         , to_char(n.original_loan_to_value_ltv) as n12
         , to_char(o.original_interest_rate) as o13
         , to_char(n.original_interest_rate) as n13
         , to_char(o.channel) as o14
         , to_char(n.channel) as n14
         , to_char(o.prepayment_penalty_indicator) as o15
         , to_char(n.prepayment_penalty_indicator) as n15
         , to_char(o.amortization_type) as o16
         , to_char(n.amortization_type) as n16
         , to_char(o.property_state) as o17
         , to_char(n.property_state) as n17
         , to_char(o.property_type) as o18
         , to_char(n.property_type) as n18
         , to_char(o.postal_code) as o19
         , to_char(n.postal_code) as n19
         , to_char(o.loan_purpose) as o20
         , to_char(n.loan_purpose) as n20
         , to_char(o.original_loan_term) as o21
         , to_char(n.original_loan_term) as n21
         , to_char(o.number_of_borrowers) as o22
         , to_char(n.number_of_borrowers) as n22
         , to_char(o.seller_name) as o23
         , to_char(n.seller_name) as n23
         , to_char(o.super_conforming_flag) as o24
         , to_char(n.super_conforming_flag) as n24
         , to_char(o.pre_harp_loan_sequence_number) as o25
         , to_char(n.pre_harp_loan_sequence_number) as n25
         , to_char(o.special_eligibility_program) as o26
         , to_char(n.special_eligibility_program) as n26
         , to_char(o.harp_indicator) as o27
         , to_char(n.harp_indicator) as n27
         , to_char(o.property_valuation_method) as o28
         , to_char(n.property_valuation_method) as n28
         , to_char(o.interest_only_i_o_indicator) as o29
         , to_char(n.interest_only_i_o_indicator) as n29
         , to_char(o.origination_year) as o30
         , to_char(n.origination_year) as n30
         , to_char(o.origination_quarter) as o31
         , to_char(n.origination_quarter) as n31
      from old_rows o
      inner join new_rows n
         on
            o.loan_identifier = n.loan_identifier
   )

   select
      in_old_release_id as old_release_id
      , in_new_release_id as new_release_id
      , 'dim_loan' as source_table
      , loan_identifier
      , monthly_reporting_period
      , lower(source_column) as source_column
      , old_value
      , new_value
   from pairs
   unpivot ((old_value, new_value) for source_column in (
      (o1, n1) as 'classic_fico'
      , (o2, n2) as 'first_payment_date'
      , (o3, n3) as 'first_time_homebuyer_indicator'
      , (o4, n4) as 'maturity_date'
      , (o5, n5) as 'msa_code'
      , (o6, n6) as 'mortgage_insurance_percentage_mi'
      , (o7, n7) as 'number_of_units'
      , (o8, n8) as 'occupancy_status'
      , (o9, n9) as 'original_combined_loan_to_value_cltv'
      , (o10, n10) as 'original_debt_to_income_dti_ratio'
      , (o11, n11) as 'original_upb'
      , (o12, n12) as 'original_loan_to_value_ltv'
      , (o13, n13) as 'original_interest_rate'
      , (o14, n14) as 'channel'
      , (o15, n15) as 'prepayment_penalty_indicator'
      , (o16, n16) as 'amortization_type'
      , (o17, n17) as 'property_state'
      , (o18, n18) as 'property_type'
      , (o19, n19) as 'postal_code'
      , (o20, n20) as 'loan_purpose'
      , (o21, n21) as 'original_loan_term'
      , (o22, n22) as 'number_of_borrowers'
      , (o23, n23) as 'seller_name'
      , (o24, n24) as 'super_conforming_flag'
      , (o25, n25) as 'pre_harp_loan_sequence_number'
      , (o26, n26) as 'special_eligibility_program'
      , (o27, n27) as 'harp_indicator'
      , (o28, n28) as 'property_valuation_method'
      , (o29, n29) as 'interest_only_i_o_indicator'
      , (o30, n30) as 'origination_year'
      , (o31, n31) as 'origination_quarter'
   ))
   where decode(old_value, new_value, 0, 1) = 1;
end compare_dim_loan;
/
