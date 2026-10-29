-- load_ads_modification_segment.sql
-- Load ads modification segment. See docs/metric_definitions.md for analytical definitions.
create or replace procedure load_ads_modification_segment(
   in_release_id in varchar2
) is
begin
   delete from ads_modification_segment
   where release_id = in_release_id;

   insert into ads_modification_segment (
      origination_year, first_mod_year, before_mod_group
      , segment_type, segment_value, modified_loans, observable_12m_loans
      , redefault_12m_loans, current_12m_loans, prepaid_12m_loans
      , redefault_12m_rate, current_12m_rate, release_id
   )
   with marked as (
      select
         p.origination_year
         , extract(year from p.first_mod_period) as first_mod_year
         , case p.is_dlq60_before_mod
            when 'Y' then 'DLQ60'
            when 'N' then 'NOT_DLQ60'
            else 'NO_PRIOR'
         end as before_mod_group
         , seg.segment_type
         , seg.segment_value
         , case when p.state_12m is not null then 1 else 0 end as observable
         , case
            when
               p.state_12m is not null
               and p.first_redefault_period is not null then 1
            else 0
         end as redefault
         , case when p.state_12m = 'C' then 1 else 0 end as is_current
         , case when p.state_12m = 'PREPAID' then 1 else 0 end as prepaid
      from dws_mod_loan_td p
      inner join v_loan_segment seg
         on
            p.release_id = seg.release_id
            and p.loan_identifier = seg.loan_identifier
      where p.release_id = in_release_id  -- noqa: RF02,RF03
   )

   , grouped as (
      select
         origination_year
         , first_mod_year
         , before_mod_group
         , segment_type
         , segment_value
         , count(*) as modified_loans
         , sum(observable) as observable_12m_loans
         , sum(redefault) as redefault_12m_loans
         , sum(is_current) as current_12m_loans
         , sum(prepaid) as prepaid_12m_loans
      from marked
      group by
         origination_year, first_mod_year, before_mod_group
         , segment_type, segment_value
   )

   select
      origination_year
      , first_mod_year
      , before_mod_group
      , segment_type
      , segment_value
      , modified_loans
      , observable_12m_loans
      , redefault_12m_loans
      , current_12m_loans
      , prepaid_12m_loans
      , redefault_12m_loans / nullif(observable_12m_loans, 0)
         as redefault_12m_rate
      , current_12m_loans / nullif(observable_12m_loans, 0)
         as current_12m_rate
      , in_release_id as release_id
   from grouped;
end load_ads_modification_segment;
/
