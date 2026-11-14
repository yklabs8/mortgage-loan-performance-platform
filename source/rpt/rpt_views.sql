-- Name: rpt_views.sql
-- Purpose: read-only report views for consumers: Tableau exports and the review application's monthly report read only these views,
--          never the underlying tables; read-only accounts are granted select on these views only.
--          The views have the same columns as the underlying ADS tables plus a few columns consumers often need and easily get wrong (each says how it is computed)
-- Requires: the four ADS tables and dim_case_status exist
-- Called by: scripts/run_sql.sh source/rpt/rpt_views.sql (rerun after changing a view; create or replace, safe to rerun)

-- rpt_views.sql
-- Rpt views. See docs/metric_definitions.md for analytical definitions.
create or replace view rpt_vintage_dlq60_curve as
select
   release_id
   , origination_year
   , origination_quarter
   , months_on_book
   , cohort_loans
   , eligible_loans
   , cum_dlq60_loans
   , cum_dlq60_rate
   , case
      when eligible_loans >= 0.95 * cohort_loans then 'Y' else 'N'
   end as is_plottable
from ads_vintage_dlq60_curve;

-- Delinquency transitions: counts only. Rates must be "sum of numerators / sum for the same prior-month state", so no per-row rate is given here, to avoid averaging rates
create or replace view rpt_dlq_transition_monthly as
select
   release_id
   , origination_year
   , monthly_reporting_period
   , from_state
   , from_state_order
   , to_state
   , to_state_order
   , loan_count
from ads_dlq_transition_monthly;


create or replace view rpt_modification_outcome as
select
   release_id
   , origination_year
   , first_mod_year
   , before_mod_group
   , modified_loans
   , observable_12m_loans
   , redefault_12m_loans
   , current_12m_loans
   , prepaid_12m_loans
   , redefault_12m_rate
   , current_12m_rate
from ads_modification_outcome;


create or replace view rpt_review_case_monthly as
select
   a.opened_month
   , a.data_source
   , a.rule_code
   , a.current_status
   , s.status_name
   , a.case_count
   , a.escalated_count
   , a.reopened_count
   , a.closed_count
   , a.total_days_to_close
   , a.refreshed_at
   , case
      when a.closed_count > 0
         then round(a.total_days_to_close / a.closed_count, 1)
   end as avg_days_to_close
from ads_review_case_monthly a
inner join dim_case_status s
   on a.current_status = s.status_code;

-- noqa: disable=LT05
comment on table rpt_vintage_dlq60_curve is 'Report view: cumulative 60+ delinquency curve (ads_vintage_dlq60_curve) plus is_plottable (plotted only when the denominator is at least 95% of the quarter''s loans)';
comment on table rpt_dlq_transition_monthly is 'Report view: delinquency transition counts (ads_dlq_transition_monthly); compute rates by dividing sums';
comment on table rpt_modification_outcome is 'Report view: modification outcomes (ads_modification_outcome)';
comment on table rpt_review_case_monthly is 'Report view: monthly review report (ads_review_case_monthly) plus status name and average days to close per row';
-- noqa: enable=LT05
