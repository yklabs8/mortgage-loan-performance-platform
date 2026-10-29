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

