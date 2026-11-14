"""Columns and types of the new Freddie Mac format (from R47), for Spark.

Column names and order are identical to Oracle's ods_orig and ods_perf (copied from the column lists in source/ods/ods_orig.sql and ods_perf.sql);
type conversions and renames are the same as the new-format part of Oracle's load_dim_loan and load_dwd_loan_monthly_perf.
Called by: the Spark pipeline and spark/sample_candidates.py.
"""

ORIG_COLUMNS = [  # origination file, 31 columns (File Layout July 2026 columns 1-31)
    "classic_fico",
    "first_payment_date",
    "first_time_homebuyer_indicator",
    "maturity_date",
    "metropolitan_statistical_area_msa_or_metropolitan_division",
    "mortgage_insurance_percentage_mi",
    "number_of_units",
    "occupancy_status",
    "original_combined_loan_to_value_cltv",
    "original_debt_to_income_dti_ratio",
    "original_upb",
    "original_loan_to_value_ltv",
    "original_interest_rate",
    "channel",
    "prepayment_penalty_indicator",
    "amortization_type",
    "property_state",
    "property_type",
    "postal_code",
    "loan_identifier",
    "loan_purpose",
    "original_loan_term",
    "number_of_borrowers",
    "seller_name",
    "super_conforming_flag",
    "pre_harp_loan_sequence_number",
    "special_eligibility_program",
    "harp_indicator",
    "property_valuation_method",
    "interest_only_i_o_indicator",
    "vantagescore_4_0",
]

PERF_COLUMNS = [  # monthly file, 35 columns (File Layout July 2026 columns 1-35)
    "loan_identifier",
    "monthly_reporting_period",
    "current_actual_upb",
    "current_loan_delinquency_status",
    "loan_age",
    "remaining_months_to_legal_maturity",
    "underwriting_defect_and_major_servicing_defect_settlement_date",
    "modification_flag",
    "zero_balance_code",
    "zero_balance_effective_date",
    "current_interest_rate",
    "current_non_interest_bearing_upb",
    "due_date_of_last_paid_installment_ddlpi",
    "mi_recoveries",
    "net_sales_proceeds",
    "non_mi_recoveries",
    "total_expenses",
    "legal_costs",
    "maintenance_and_preservation_costs",
    "taxes_and_insurance",
    "miscellaneous_expenses",
    "actual_loss",
    "cumulative_modification_costs",
    "interest_rate_step_indicator",
    "payment_deferral_flag",
    "estimated_loan_to_value_eltv",
    "zero_balance_removal_upb",
    "delinquent_accrued_interest",
    "delinquency_due_to_disaster",
    "borrower_assistance_plan",
    "current_period_modification_costs",
    "current_interest_bearing_upb",
    "mortgage_insurance_cancellation_indicator",
    "servicer_name",
    "bankruptcy_cramdown_costs",
]

# Columns converted to dates (YYYYMM -> first day of the month), same as Oracle's to_date(..., 'YYYYMM')
ORIG_DATE_COLUMNS = {"first_payment_date", "maturity_date"}
PERF_DATE_COLUMNS = {
    "monthly_reporting_period",
    "underwriting_defect_and_major_servicing_defect_settlement_date",
    "zero_balance_effective_date",
    "due_date_of_last_paid_installment_ddlpi",
}

# Columns kept as text (codes, flags, names), same as Oracle; all other columns become numbers
ORIG_TEXT_COLUMNS = {
    "first_time_homebuyer_indicator",
    "metropolitan_statistical_area_msa_or_metropolitan_division",
    "occupancy_status",
    "channel",
    "prepayment_penalty_indicator",
    "amortization_type",
    "property_state",
    "property_type",
    "postal_code",
    "loan_identifier",
    "loan_purpose",
    "seller_name",
    "super_conforming_flag",
    "pre_harp_loan_sequence_number",
    "special_eligibility_program",
    "harp_indicator",
    "property_valuation_method",
    "interest_only_i_o_indicator",
}
PERF_TEXT_COLUMNS = {
    "loan_identifier",
    "current_loan_delinquency_status",
    "modification_flag",
    "zero_balance_code",
    "net_sales_proceeds",
    "interest_rate_step_indicator",
    "payment_deferral_flag",
    "delinquency_due_to_disaster",
    "borrower_assistance_plan",
    "mortgage_insurance_cancellation_indicator",
    "servicer_name",
}

# All other columns become numbers with the official precision (total digits, scale), same as Oracle's dim_loan and dwd_loan_monthly_perf
# File Layout July 2026 "Numeric 4" = 4-digit integer, "Numeric - 12,2" = 12 digits with 2 decimals;
# column 12 (non-interest-bearing UPB) has no scale in the File Layout and is set to 12,2 from the User Guide p.10 equation and p.12 "$ Amount".
# Before conversion DQ017 checks digit counts against this (spark_quality.digits_fit); anything out of range fails the batch instead of being rounded silently
AMOUNT = (12, 2)
NUMERIC_TYPES = {
    "classic_fico": (4, 0),
    "mortgage_insurance_percentage_mi": (3, 0),
    "number_of_units": (2, 0),
    "original_combined_loan_to_value_cltv": (3, 0),
    "original_debt_to_income_dti_ratio": (3, 0),
    "original_upb": (12, 0),
    "original_loan_to_value_ltv": (3, 0),
    "original_interest_rate": (6, 3),
    "original_loan_term": (3, 0),
    "number_of_borrowers": (2, 0),
    "vantagescore_4_0": (4, 0),
    "current_actual_upb": AMOUNT,
    "loan_age": (3, 0),
    "remaining_months_to_legal_maturity": (3, 0),
    "current_interest_rate": (8, 3),
    "current_non_interest_bearing_upb": AMOUNT,
    "mi_recoveries": AMOUNT,
    "non_mi_recoveries": AMOUNT,
    "total_expenses": AMOUNT,
    "legal_costs": AMOUNT,
    "maintenance_and_preservation_costs": AMOUNT,
    "taxes_and_insurance": AMOUNT,
    "miscellaneous_expenses": AMOUNT,
    "actual_loss": AMOUNT,
    "cumulative_modification_costs": AMOUNT,
    "estimated_loan_to_value_eltv": (4, 0),
    "zero_balance_removal_upb": AMOUNT,
    "delinquent_accrued_interest": AMOUNT,
    "current_period_modification_costs": AMOUNT,
    "current_interest_bearing_upb": AMOUNT,
    "bankruptcy_cramdown_costs": AMOUNT,
}


def decimal_type(column):
    precision, scale = NUMERIC_TYPES[column]
    return f"decimal({precision},{scale})"


# Renames: same column names as Oracle's dim_loan and dwd_loan_monthly_perf
RENAMES = {
    "metropolitan_statistical_area_msa_or_metropolitan_division": "msa_code",
    "underwriting_defect_and_major_servicing_defect_settlement_date": (
        "defect_settlement_date"
    ),
}
