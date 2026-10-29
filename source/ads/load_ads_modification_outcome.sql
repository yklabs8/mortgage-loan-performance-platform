-- load_ads_modification_outcome.sql
-- Load ads modification outcome. See docs/metric_definitions.md for analytical definitions.
create or replace procedure load_ads_modification_outcome(
   in_release_id in varchar2
) is
begin
   delete from ads_modification_outcome
   where release_id = in_release_id;

   insert into ads_modification_outcome (
      origination_year
      , first_mod_year
      , before_mod_group
      , modified_loans
      , observable_12m_loans
      , redefault_12m_loans
      , current_12m_loans
      , prepaid_12m_loans
      , redefault_12m_rate
      , current_12m_rate
      , release_id
   )
   with

   dws as (
      select
         origination_year
         , extract(year from first_mod_period) as first_mod_year
         , case is_dlq60_before_mod
            when 'Y' then 'DLQ60'
            when 'N' then 'NOT_DLQ60'
            else 'NO_PRIOR'
         end as before_mod_group
         , case when state_12m is not null then 1 else 0 end as observable
         , case
            when state_12m is not null and first_redefault_period is not null
               then 1
            else 0
         end as redefault
         , case when state_12m = 'C' then 1 else 0 end as is_current
         , case when state_12m = 'PREPAID' then 1 else 0 end as prepaid
         , release_id
      from dws_mod_loan_td
      where release_id = in_release_id
   )

   , grouped as (
      select
         origination_year
         , first_mod_year
         , before_mod_group
         , release_id
         , count(*) as modified_loans
         , sum(observable) as observable_12m_loans
         , sum(redefault) as redefault_12m_loans
         , sum(is_current) as current_12m_loans
         , sum(prepaid) as prepaid_12m_loans
      from dws
      group by origination_year, first_mod_year, before_mod_group, release_id
   )

   select
      origination_year
      , first_mod_year
      , before_mod_group
      , modified_loans
      , observable_12m_loans
      , redefault_12m_loans
      , current_12m_loans
      , prepaid_12m_loans
      , redefault_12m_loans
      / nullif(observable_12m_loans, 0) as redefault_12m_rate
      , current_12m_loans / nullif(observable_12m_loans, 0) as current_12m_rate
      , release_id
   from grouped;
end load_ads_modification_outcome;
/
