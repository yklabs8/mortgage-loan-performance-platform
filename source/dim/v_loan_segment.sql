-- v_loan_segment.sql
-- V loan segment. See docs/metric_definitions.md for analytical definitions.
create or replace view v_loan_segment as
with attrs as (
   select
      d.release_id
      , d.loan_identifier
      , d.fico_band
      , d.ltv_band
      , d.property_state
      , g.census_region_name
      , d.channel
      , d.loan_purpose
      , d.property_type
      , d.amortization_type
      , d.harp_indicator
   from dim_loan d
   left join dim_geography g on d.property_state = g.state_code
)

select
   release_id
   , loan_identifier
   , 'FICO' as segment_type
   , fico_band as segment_value
from attrs
union all
select
   release_id
   , loan_identifier
   , 'LTV' as segment_type
   , ltv_band as segment_value
from attrs
union all
select
   release_id
   , loan_identifier
   , 'STATE' as segment_type
   , coalesce(property_state, 'UNKNOWN') as segment_value
from attrs
union all
select
   release_id
   , loan_identifier
   , 'REGION' as segment_type
   , coalesce(census_region_name, 'UNKNOWN') as segment_value
from attrs
union all
select
   release_id
   , loan_identifier
   , 'CHANNEL' as segment_type
   , coalesce(channel, 'UNKNOWN') as segment_value
from attrs
union all
select
   release_id
   , loan_identifier
   , 'LOAN_PURPOSE' as segment_type
   , coalesce(loan_purpose, 'UNKNOWN') as segment_value
from attrs
union all
select
   release_id
   , loan_identifier
   , 'PROPERTY_TYPE' as segment_type
   , coalesce(property_type, 'UNKNOWN') as segment_value
from attrs
union all
select
   release_id
   , loan_identifier
   , 'AMORTIZATION' as segment_type
   , coalesce(amortization_type, 'UNKNOWN') as segment_value
from attrs
union all
select
   release_id
   , loan_identifier
   , 'HARP' as segment_type
   , coalesce(harp_indicator, 'UNKNOWN') as segment_value
from attrs;
