-- dim_loan.sql
-- Dim loan. See docs/metric_definitions.md for analytical definitions.
-- noqa: disable=PRS
create table dim_loan (
   classic_fico number(4)
   , fico_band varchar2(12) generated always as (
      case
         when classic_fico is null or classic_fico = 9999 then 'UNKNOWN'
         when classic_fico < 620 then '<620'
         when classic_fico < 680 then '[620,680)'
         when classic_fico < 740 then '[680,740)'
         else '>=740'
      end
   ) virtual
   , first_payment_date date
   , first_time_homebuyer_indicator varchar2(1)
   , maturity_date date
   , msa_code varchar2(5)
   , mortgage_insurance_percentage_mi number(3)
   , number_of_units number(2)
   , occupancy_status varchar2(1)
   , original_combined_loan_to_value_cltv number(3)
   , original_debt_to_income_dti_ratio number(3)
   , original_upb number(12)
   , original_loan_to_value_ltv number(3)
   , ltv_band varchar2(12) generated always as (
      case
         when original_loan_to_value_ltv is null
            or original_loan_to_value_ltv = 999 then 'UNKNOWN'
         when original_loan_to_value_ltv <= 60 then '<=60'
         when original_loan_to_value_ltv <= 80 then '(60,80]'
         when original_loan_to_value_ltv <= 90 then '(80,90]'
         when original_loan_to_value_ltv <= 97 then '(90,97]'
         else '>97'
      end
   ) virtual
   , original_interest_rate number(6, 3)
   , channel varchar2(1)
   , prepayment_penalty_indicator varchar2(1)
   , amortization_type varchar2(5)
   , property_state varchar2(2)
   , property_type varchar2(2)
   , postal_code varchar2(3)
   , loan_identifier varchar2(12)
   , loan_purpose varchar2(1)
   , original_loan_term number(3)
   , number_of_borrowers number(2)
   , seller_name varchar2(60)
   , super_conforming_flag varchar2(1)
   , pre_harp_loan_sequence_number varchar2(12)
   , special_eligibility_program varchar2(1)
   , harp_indicator varchar2(1)
   , property_valuation_method varchar2(1)
   , interest_only_i_o_indicator varchar2(1)
   , vantagescore_4_0 number(4)
   , origination_year number(4)
   , origination_quarter number(1)
   , release_id varchar2(10) not null
   , data_source varchar2(3) not null
   , comparable_flag varchar2(1) default 'Y' not null
   , loan_key number generated always as identity
   , loan_durable_key number not null
   , constraint dim_loan_pk primary key (loan_key)
   , constraint dim_loan_release_loan_uk unique (release_id, loan_identifier)
   , constraint dim_loan_release_durable_uk unique (
      release_id, loan_durable_key
   )
   , constraint dim_loan_data_source_ck check (data_source in ('FRE'))
   , constraint dim_loan_comparable_ck check (comparable_flag in ('Y', 'N'))
   , constraint dl_dg_fk foreign key (property_state)
   references dim_geography (state_code)
   , constraint dl_dlkm_fk foreign key (loan_durable_key)
   references dim_loan_key_map (loan_durable_key)
);
-- noqa: enable=PRS

-- noqa: disable=LT05
comment on table dim_loan is 'DIM: one loan per release. Surrogate primary key loan_key; unique release_id plus loan_identifier. Origination attributes are converted from ods_orig or ods_orig_pre202607; source codes and special unavailable values are retained. Release differences represent source corrections rather than SCD Type 2 business changes.';
comment on column dim_loan.classic_fico is 'Classic FICO® | Source: ods_orig.classic_fico (File Layout July 2026 column 1, Numeric) | Convert text to NUMBER(4) using the official precision; DQ017 checks the digits before conversion and rejects the batch if a value does not fit, so nothing is rounded silently';
comment on column dim_loan.fico_band is 'Credit-score band, internal analysis definition (not an official rule); 9999 and NULL become UNKNOWN. Computed from classic_fico.';
comment on column dim_loan.first_payment_date is 'First Payment Date | Source: ods_orig.first_payment_date (File Layout July 2026 column 2, Date) | Convert YYYYMM to the first day of that month';
comment on column dim_loan.first_time_homebuyer_indicator is 'First Time Homebuyer Indicator | Source: ods_orig.first_time_homebuyer_indicator (File Layout July 2026 column 3, Alpha) | Retain source text';
comment on column dim_loan.maturity_date is 'Maturity Date | Source: ods_orig.maturity_date (File Layout July 2026 column 4, Date) | Convert YYYYMM to the first day of that month';
comment on column dim_loan.msa_code is 'Metropolitan Statistical Area (MSA) Or Metropolitan Division | Source: ods_orig.metropolitan_statistical_area_msa_or_metropolitan_division (File Layout July 2026 column 5, Numeric) | Retain text: a code rather than an arithmetic value; Column name shortened to msa_code (official description uses MSA Code)';
comment on column dim_loan.mortgage_insurance_percentage_mi is 'Mortgage Insurance Percentage (MI %) | Source: ods_orig.mortgage_insurance_percentage_mi (File Layout July 2026 column 6, Numeric) | Convert text to NUMBER(3) using the official precision; DQ017 checks the digits before conversion and rejects the batch if a value does not fit, so nothing is rounded silently';
comment on column dim_loan.number_of_units is 'Number of Units | Source: ods_orig.number_of_units (File Layout July 2026 column 7, Numeric) | Convert text to NUMBER(2) using the official precision; DQ017 checks the digits before conversion and rejects the batch if a value does not fit, so nothing is rounded silently';
comment on column dim_loan.occupancy_status is 'Occupancy Status | Source: ods_orig.occupancy_status (File Layout July 2026 column 8, Alpha) | Retain source text';
comment on column dim_loan.original_combined_loan_to_value_cltv is 'Original Combined Loan-to-Value (CLTV) | Source: ods_orig.original_combined_loan_to_value_cltv (File Layout July 2026 column 9, Numeric) | Convert text to NUMBER(3) using the official precision; DQ017 checks the digits before conversion and rejects the batch if a value does not fit, so nothing is rounded silently';
comment on column dim_loan.original_debt_to_income_dti_ratio is 'Original Debt-to-Income (DTI) Ratio | Source: ods_orig.original_debt_to_income_dti_ratio (File Layout July 2026 column 10, Numeric) | Convert text to NUMBER(3) using the official precision; DQ017 checks the digits before conversion and rejects the batch if a value does not fit, so nothing is rounded silently';
comment on column dim_loan.original_upb is 'Original UPB | Source: ods_orig.original_upb (File Layout July 2026 column 11, Numeric) | Convert text to NUMBER(12) using the official precision; DQ017 checks the digits before conversion and rejects the batch if a value does not fit, so nothing is rounded silently';
comment on column dim_loan.original_loan_to_value_ltv is 'Original Loan-to-Value (LTV) | Source: ods_orig.original_loan_to_value_ltv (File Layout July 2026 column 12, Numeric) | Convert text to NUMBER(3) using the official precision; DQ017 checks the digits before conversion and rejects the batch if a value does not fit, so nothing is rounded silently';
comment on column dim_loan.ltv_band is 'Original LTV band, internal analysis definition (not an official rule); 999 and NULL become UNKNOWN. Computed from original_loan_to_value_ltv.';
comment on column dim_loan.original_interest_rate is 'Original Interest Rate | Source: ods_orig.original_interest_rate (File Layout July 2026 column 13, Numeric - 6,3) | Convert text to NUMBER(6,3) using the official precision; DQ017 checks the digits before conversion and rejects the batch if a value does not fit, so nothing is rounded silently';
comment on column dim_loan.channel is 'Channel | Source: ods_orig.channel (File Layout July 2026 column 14, Alpha) | Retain source text';
comment on column dim_loan.prepayment_penalty_indicator is 'Prepayment Penalty Indicator | Source: ods_orig.prepayment_penalty_indicator (File Layout July 2026 column 15, Alpha) | Retain source text';
comment on column dim_loan.amortization_type is 'Amortization Type | Source: ods_orig.amortization_type (File Layout July 2026 column 16, Alpha) | Retain source text';
comment on column dim_loan.property_state is 'Property State | Source: ods_orig.property_state (File Layout July 2026 column 17, Alpha) | Retain source text; Foreign key to dim_geography (state or territory, User Guide p.7)';
comment on column dim_loan.property_type is 'Property Type | Source: ods_orig.property_type (File Layout July 2026 column 18, Alpha) | Retain source text';
comment on column dim_loan.postal_code is 'Postal Code | Source: ods_orig.postal_code (File Layout July 2026 column 19, Alpha) | Retain source text';
comment on column dim_loan.loan_identifier is 'Loan Identifier | Source: ods_orig.loan_identifier (File Layout July 2026 column 20, Alpha Numeric - PYYQnXXXXXXX) | Retain source text';
comment on column dim_loan.loan_purpose is 'Loan Purpose | Source: ods_orig.loan_purpose (File Layout July 2026 column 21, Alpha) | Retain source text';
comment on column dim_loan.original_loan_term is 'Original Loan Term | Source: ods_orig.original_loan_term (File Layout July 2026 column 22, Numeric) | Convert text to NUMBER(3) using the official precision; DQ017 checks the digits before conversion and rejects the batch if a value does not fit, so nothing is rounded silently';
comment on column dim_loan.number_of_borrowers is 'Number of Borrowers | Source: ods_orig.number_of_borrowers (File Layout July 2026 column 23, Numeric) | Convert text to NUMBER(2) using the official precision; DQ017 checks the digits before conversion and rejects the batch if a value does not fit, so nothing is rounded silently';
comment on column dim_loan.seller_name is 'Seller Name | Source: ods_orig.seller_name (File Layout July 2026 column 24, Alpha Numeric) | Retain source text';
comment on column dim_loan.super_conforming_flag is 'Super Conforming Flag | Source: ods_orig.super_conforming_flag (File Layout July 2026 column 25, Alpha) | Retain source text';
comment on column dim_loan.pre_harp_loan_sequence_number is 'Pre-HARP Loan Sequence Number | Source: ods_orig.pre_harp_loan_sequence_number (File Layout July 2026 column 26, Alpha Numeric - PYYQnXXXXXXX) | Retain source text';
comment on column dim_loan.special_eligibility_program is 'Special Eligibility Program | Source: ods_orig.special_eligibility_program (File Layout July 2026 column 27, Alpha Numeric) | Retain source text';
comment on column dim_loan.harp_indicator is 'HARP Indicator | Source: ods_orig.harp_indicator (File Layout July 2026 column 28, Alpha) | Retain source text';
comment on column dim_loan.property_valuation_method is 'Property Valuation Method | Source: ods_orig.property_valuation_method (File Layout July 2026 column 29, Numeric) | Retain text: a code rather than an arithmetic value';
comment on column dim_loan.interest_only_i_o_indicator is 'Interest Only (I/O) Indicator | Source: ods_orig.interest_only_i_o_indicator (File Layout July 2026 column 30, Alpha) | Retain source text';
comment on column dim_loan.vantagescore_4_0 is 'VantageScore® 4.0 | Source: ods_orig.vantagescore_4_0 (File Layout July 2026 column 31, Numeric) | Convert text to NUMBER(4) using the official precision; DQ017 checks the digits before conversion and rejects the batch if a value does not fit, so nothing is rounded silently';
comment on column dim_loan.origination_year is 'Origination year from YY in PYYQn (User Guide p.7). Data starts in 1999 (p.16): 99 maps to 1999; other values map to 20YY.';
comment on column dim_loan.origination_quarter is 'Origination quarter from n in PYYQn (User Guide p.7)';
comment on column dim_loan.release_id is 'Source data release, e.g. R47';
comment on column dim_loan.data_source is 'Source agency: FRE = Freddie Mac; column added by the warehouse';
comment on column dim_loan.loan_key is 'Surrogate loan key within a release; MERGE retains an existing key on reload. Facts reference this key. External applications should retain business keys.';
comment on column dim_loan.loan_durable_key is 'Durable key from dim_loan_key_map, stable across releases for the same agency and loan ID';
comment on column dim_loan.comparable_flag is 'Comparability eligibility: Y/N. Excludes nonstandard source populations using the four Freddie rules in metric definitions section 8.';
-- noqa: enable=LT05
