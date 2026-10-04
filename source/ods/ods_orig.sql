-- Name: ods_orig.sql
-- Purpose: create ODS table ods_orig: the Freddie origination file (sample_orig_YYYY.txt / orig_YYYYQn.txt) landed as-is
-- Requires: user loan_dw created (scripts/1_create_db_user.sh)
-- Called by: scripts/run_sql.sh source/ods/ods_orig.sql
-- Column names, order and lengths: official Freddie Mac File Headers and File Layout (R47, July 2026 version)

-- noqa: disable=all
create table ods_orig (
   classic_fico varchar2(4)
   , first_payment_date varchar2(6)
   , first_time_homebuyer_indicator varchar2(1)
   , maturity_date varchar2(6)
   , metropolitan_statistical_area_msa_or_metropolitan_division varchar2(5)
   , mortgage_insurance_percentage_mi varchar2(3)
   , number_of_units varchar2(2)
   , occupancy_status varchar2(1)
   , original_combined_loan_to_value_cltv varchar2(3)
   , original_debt_to_income_dti_ratio varchar2(3)
   , original_upb varchar2(12)
   , original_loan_to_value_ltv varchar2(3)
   , original_interest_rate varchar2(6)
   , channel varchar2(1)
   , prepayment_penalty_indicator varchar2(1)
   , amortization_type varchar2(5)
   , property_state varchar2(2)
   , property_type varchar2(2)
   , postal_code varchar2(3)
   , loan_identifier varchar2(12)
   , loan_purpose varchar2(1)
   , original_loan_term varchar2(3)
   , number_of_borrowers varchar2(2)
   , seller_name varchar2(60)
   , super_conforming_flag varchar2(1)
   , pre_harp_loan_sequence_number varchar2(12)
   , special_eligibility_program varchar2(1)
   , harp_indicator varchar2(1)
   , property_valuation_method varchar2(1)
   , interest_only_i_o_indicator varchar2(1)
   , vantagescore_4_0 varchar2(4)
   , release_id varchar2(10) not null
   , source_file varchar2(100) not null
   , constraint ods_orig_pk primary key (release_id, loan_identifier)
)
partition by list (release_id, source_file) (
   partition p_default values (default)
);
-- noqa: enable=all

-- The table and column comments below spell out the official name, column position, type and maximum length,
-- so their lines exceed 80 characters; line length is not checked in this block (project convention)
-- noqa: disable=LT05
comment on table ods_orig is 'ODS: the Freddie origination file (sample_orig_YYYY.txt / orig_YYYYQn.txt) landed as-is. One row per loan per release; primary key release_id + loan_identifier. All values stored as text, unchanged. Columns 1–31 follow the order of the File Layout (July 2026); the last two columns, release_id and source_file, are added by this project.';

comment on column ods_orig.classic_fico is 'Classic FICO® | File Layout (July 2026) column 1 | Numeric, max length 4';
comment on column ods_orig.first_payment_date is 'First Payment Date | File Layout (July 2026) column 2 | Date, max length 6';
comment on column ods_orig.first_time_homebuyer_indicator is 'First Time Homebuyer Indicator | File Layout (July 2026) column 3 | Alpha, max length 1';
comment on column ods_orig.maturity_date is 'Maturity Date | File Layout (July 2026) column 4 | Date, max length 6';
comment on column ods_orig.metropolitan_statistical_area_msa_or_metropolitan_division is 'Metropolitan Statistical Area (MSA) Or Metropolitan Division | File Layout (July 2026) column 5 | Numeric, max length 5';
comment on column ods_orig.mortgage_insurance_percentage_mi is 'Mortgage Insurance Percentage (MI %) | File Layout (July 2026) column 6 | Numeric, max length 3';
comment on column ods_orig.number_of_units is 'Number of Units | File Layout (July 2026) column 7 | Numeric, max length 2';
comment on column ods_orig.occupancy_status is 'Occupancy Status | File Layout (July 2026) column 8 | Alpha, max length 1';
comment on column ods_orig.original_combined_loan_to_value_cltv is 'Original Combined Loan-to-Value (CLTV) | File Layout (July 2026) column 9 | Numeric, max length 3';
comment on column ods_orig.original_debt_to_income_dti_ratio is 'Original Debt-to-Income (DTI) Ratio | File Layout (July 2026) column 10 | Numeric, max length 3';
comment on column ods_orig.original_upb is 'Original UPB | File Layout (July 2026) column 11 | Numeric, max length 12';
comment on column ods_orig.original_loan_to_value_ltv is 'Original Loan-to-Value (LTV) | File Layout (July 2026) column 12 | Numeric, max length 3';
comment on column ods_orig.original_interest_rate is 'Original Interest Rate | File Layout (July 2026) column 13 | Numeric - 6,3, max length 6';
comment on column ods_orig.channel is 'Channel | File Layout (July 2026) column 14 | Alpha, max length 1';
comment on column ods_orig.prepayment_penalty_indicator is 'Prepayment Penalty Indicator | File Layout (July 2026) column 15 | Alpha, max length 1';
comment on column ods_orig.amortization_type is 'Amortization Type | File Layout (July 2026) column 16 | Alpha, max length 5';
comment on column ods_orig.property_state is 'Property State | File Layout (July 2026) column 17 | Alpha, max length 2';
comment on column ods_orig.property_type is 'Property Type | File Layout (July 2026) column 18 | Alpha, max length 2';
comment on column ods_orig.postal_code is 'Postal Code | File Layout (July 2026) column 19 | Alpha, max length 3';
comment on column ods_orig.loan_identifier is 'Loan Identifier | File Layout (July 2026) column 20 | Alpha Numeric - PYYQnXXXXXXX, max length 12';
comment on column ods_orig.loan_purpose is 'Loan Purpose | File Layout (July 2026) column 21 | Alpha, max length 1';
comment on column ods_orig.original_loan_term is 'Original Loan Term | File Layout (July 2026) column 22 | Numeric, max length 3';
comment on column ods_orig.number_of_borrowers is 'Number of Borrowers | File Layout (July 2026) column 23 | Numeric, max length 2';
comment on column ods_orig.seller_name is 'Seller Name | File Layout (July 2026) column 24 | Alpha Numeric, max length 60';
comment on column ods_orig.super_conforming_flag is 'Super Conforming Flag | File Layout (July 2026) column 25 | Alpha, max length 1';
comment on column ods_orig.pre_harp_loan_sequence_number is 'Pre-HARP Loan Sequence Number | File Layout (July 2026) column 26 | Alpha Numeric - PYYQnXXXXXXX, max length 12';
comment on column ods_orig.special_eligibility_program is 'Special Eligibility Program | File Layout (July 2026) column 27 | Alpha Numeric, max length 1';
comment on column ods_orig.harp_indicator is 'HARP Indicator | File Layout (July 2026) column 28 | Alpha, max length 1';
comment on column ods_orig.property_valuation_method is 'Property Valuation Method | File Layout (July 2026) column 29 | Numeric, max length 1';
comment on column ods_orig.interest_only_i_o_indicator is 'Interest Only (I/O) Indicator | File Layout (July 2026) column 30 | Alpha, max length 1';
comment on column ods_orig.vantagescore_4_0 is 'VantageScore® 4.0 | File Layout (July 2026) column 31 | Numeric, max length 4';
comment on column ods_orig.release_id is 'Freddie data release, e.g. R47 (column added by this project; length 10 is a project convention, enough for such codes)';
comment on column ods_orig.source_file is 'Source file name; within a release, data is replaced file by file; traceable (column added by this project)';
-- noqa: enable=LT05
