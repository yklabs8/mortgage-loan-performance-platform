-- load_dim_loan.sql
-- MERGE preserves existing surrogate keys. Assign durable keys once per agency and loan ID. New and earlier layouts are normalized using official Disclosure Changes v1.2; source special values remain explicit. Reject mismatched source, merged and dimension counts.
create or replace procedure load_dim_loan(
   in_release_id in varchar2
) is
   l_ods_rows pls_integer;
   l_ods_new pls_integer;
   l_ods_old pls_integer;
   l_merged pls_integer;
   l_dim_rows pls_integer;
begin
   merge into dim_loan_key_map t
   using (
      select
         'FRE' as data_source
         , loan_identifier
      from ods_orig
      where release_id = in_release_id
      union
      select
         'FRE' as data_source
         , loan_sequence_number as loan_identifier
      from ods_orig_pre202607
      where release_id = in_release_id
   ) s
      on (
         t.data_source = s.data_source
         and t.loan_identifier = s.loan_identifier
      )
   when not matched then
      insert (data_source, loan_identifier, first_release_id)
      values (s.data_source, s.loan_identifier, in_release_id);

   merge into dim_loan t
   using (

      select
         to_number(classic_fico) as classic_fico
         , to_date(first_payment_date, 'YYYYMM') as first_payment_date
         , first_time_homebuyer_indicator
         , to_date(maturity_date, 'YYYYMM') as maturity_date
         , metropolitan_statistical_area_msa_or_metropolitan_division
            as msa_code
         , to_number(
            mortgage_insurance_percentage_mi
         ) as mortgage_insurance_percentage_mi
         , to_number(number_of_units) as number_of_units
         , occupancy_status
         , to_number(
            original_combined_loan_to_value_cltv
         ) as original_combined_loan_to_value_cltv
         , to_number(
            original_debt_to_income_dti_ratio
         ) as original_debt_to_income_dti_ratio
         , to_number(original_upb) as original_upb
         , to_number(original_loan_to_value_ltv) as original_loan_to_value_ltv
         , to_number(original_interest_rate) as original_interest_rate
         , channel
         , prepayment_penalty_indicator
         , amortization_type
         , property_state
         , property_type
         , postal_code
         , loan_identifier
         , loan_purpose
         , to_number(original_loan_term) as original_loan_term
         , to_number(number_of_borrowers) as number_of_borrowers
         , seller_name
         , super_conforming_flag
         , pre_harp_loan_sequence_number
         , special_eligibility_program
         , harp_indicator
         , property_valuation_method
         , interest_only_i_o_indicator
         , to_number(vantagescore_4_0) as vantagescore_4_0
         , case
            when substr(loan_identifier, 2, 2) = '99' then 1999
            else 2000 + to_number(substr(loan_identifier, 2, 2))
         end as origination_year
         , to_number(substr(loan_identifier, 5, 1)) as origination_quarter
         , release_id
         , 'FRE' as data_source
         , (
            select km.loan_durable_key
            from dim_loan_key_map km
            where
               km.data_source = 'FRE'
               and km.loan_identifier = ods_orig.loan_identifier
         ) as loan_durable_key
      from ods_orig
      where release_id = in_release_id
      union all
      select
         to_number(credit_score) as classic_fico
         , to_date(first_payment_date, 'YYYYMM') as first_payment_date
         , first_time_homebuyer_flag as first_time_homebuyer_indicator
         , to_date(maturity_date, 'YYYYMM') as maturity_date
         , metropolitan_statistical_area_msa_or_metropolitan_division
            as msa_code
         , to_number(
            mortgage_insurance_percentage_mi
         ) as mortgage_insurance_percentage_mi
         , to_number(number_of_units) as number_of_units
         , occupancy_status
         , to_number(
            original_combined_loan_to_value_cltv
         ) as original_combined_loan_to_value_cltv
         , to_number(
            original_debt_to_income_dti_ratio
         ) as original_debt_to_income_dti_ratio
         , to_number(original_upb) as original_upb
         , to_number(original_loan_to_value_ltv) as original_loan_to_value_ltv
         , to_number(original_interest_rate) as original_interest_rate
         , channel
         , prepayment_penalty_mortgage_ppm_flag as prepayment_penalty_indicator
         , amortization_type_formerly_product_type as amortization_type
         , property_state
         , property_type
         , case
            when postal_code = '00' then '000'
            else substr(postal_code, 1, 3)
         end as postal_code
         , loan_sequence_number as loan_identifier
         , loan_purpose
         , to_number(original_loan_term) as original_loan_term
         , to_number(number_of_borrowers) as number_of_borrowers
         , case
            when upper(seller_name) = 'OTHER SELLERS' then 'OTHER'
            else seller_name
         end as seller_name
         , coalesce(super_conforming_flag, 'N') as super_conforming_flag
         , pre_harp_loan_sequence_number
         , case
            when program_indicator != '9' then program_indicator
         end as special_eligibility_program
         , coalesce(harp_indicator, 'N') as harp_indicator
         , property_valuation_method
         , interest_only_i_o_indicator
         , null as vantagescore_4_0
         , case
            when substr(loan_sequence_number, 2, 2) = '99' then 1999
            else 2000 + to_number(substr(loan_sequence_number, 2, 2))
         end as origination_year
         , to_number(substr(loan_sequence_number, 5, 1)) as origination_quarter
         , release_id
         , 'FRE' as data_source
         , (
            select km.loan_durable_key
            from dim_loan_key_map km
            where
               km.data_source = 'FRE'
               and km.loan_identifier = ods_orig_pre202607.loan_sequence_number
         ) as loan_durable_key
      from ods_orig_pre202607
      where release_id = in_release_id
   ) s
      on (
         t.release_id = s.release_id
         and t.loan_identifier = s.loan_identifier
      )
   when matched then
      update set
         classic_fico = s.classic_fico
         , first_payment_date = s.first_payment_date
         , first_time_homebuyer_indicator = s.first_time_homebuyer_indicator
         , maturity_date = s.maturity_date
         , msa_code = s.msa_code
         , mortgage_insurance_percentage_mi = s.mortgage_insurance_percentage_mi
         , number_of_units = s.number_of_units
         , occupancy_status = s.occupancy_status
         , original_combined_loan_to_value_cltv
         = s.original_combined_loan_to_value_cltv
         , original_debt_to_income_dti_ratio
         = s.original_debt_to_income_dti_ratio
         , original_upb = s.original_upb
         , original_loan_to_value_ltv = s.original_loan_to_value_ltv
         , original_interest_rate = s.original_interest_rate
         , channel = s.channel
         , prepayment_penalty_indicator = s.prepayment_penalty_indicator
         , amortization_type = s.amortization_type
         , property_state = s.property_state
         , property_type = s.property_type
         , postal_code = s.postal_code
         , loan_purpose = s.loan_purpose
         , original_loan_term = s.original_loan_term
         , number_of_borrowers = s.number_of_borrowers
         , seller_name = s.seller_name
         , super_conforming_flag = s.super_conforming_flag
         , pre_harp_loan_sequence_number = s.pre_harp_loan_sequence_number
         , special_eligibility_program = s.special_eligibility_program
         , harp_indicator = s.harp_indicator
         , property_valuation_method = s.property_valuation_method
         , interest_only_i_o_indicator = s.interest_only_i_o_indicator
         , vantagescore_4_0 = s.vantagescore_4_0
         , origination_year = s.origination_year
         , origination_quarter = s.origination_quarter
         , data_source = s.data_source
         , loan_durable_key = s.loan_durable_key
   when not matched then
      insert (
         classic_fico
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
         , loan_identifier
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
         , release_id
         , data_source
         , loan_durable_key
      )
      values (
         s.classic_fico
         , s.first_payment_date
         , s.first_time_homebuyer_indicator
         , s.maturity_date
         , s.msa_code
         , s.mortgage_insurance_percentage_mi
         , s.number_of_units
         , s.occupancy_status
         , s.original_combined_loan_to_value_cltv
         , s.original_debt_to_income_dti_ratio
         , s.original_upb
         , s.original_loan_to_value_ltv
         , s.original_interest_rate
         , s.channel
         , s.prepayment_penalty_indicator
         , s.amortization_type
         , s.property_state
         , s.property_type
         , s.postal_code
         , s.loan_identifier
         , s.loan_purpose
         , s.original_loan_term
         , s.number_of_borrowers
         , s.seller_name
         , s.super_conforming_flag
         , s.pre_harp_loan_sequence_number
         , s.special_eligibility_program
         , s.harp_indicator
         , s.property_valuation_method
         , s.interest_only_i_o_indicator
         , s.vantagescore_4_0
         , s.origination_year
         , s.origination_quarter
         , s.release_id
         , s.data_source
         , s.loan_durable_key
      );
   l_merged := sql%rowcount;

   update dim_loan
   set
      comparable_flag = case
         when
            data_source = 'FRE'
            and (
               harp_indicator = 'Y'
               or (
                  original_loan_to_value_ltv > 97
                  and original_loan_to_value_ltv != 999
               )
               or prepayment_penalty_indicator = 'Y'
               or original_loan_term < 60
               or original_loan_term >= 420
            ) then 'N'
         else 'Y'
      end
   where release_id = in_release_id;


   select count(*)
   into l_ods_new
   from ods_orig
   where release_id = in_release_id;
   select count(*)
   into l_ods_old
   from ods_orig_pre202607
   where release_id = in_release_id;
   l_ods_rows := l_ods_new + l_ods_old;
   select count(*)
   into l_dim_rows
   from dim_loan
   where release_id = in_release_id;
   if l_merged = 0 or l_merged != l_ods_rows or l_dim_rows != l_ods_rows then
      raise_application_error(
         -20001
         , 'dim_loan row count mismatch: merged ' || l_merged
         || ', rows in this release ' || l_dim_rows
         || ', ODS ' || l_ods_rows
      );
   end if;
end load_dim_loan;
/
