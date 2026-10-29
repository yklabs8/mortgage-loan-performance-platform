-- dim_geography.sql
-- Dim geography. See docs/metric_definitions.md for analytical definitions.
create table dim_geography (
   state_code varchar2(2) not null
   , state_fips varchar2(2) not null
   , state_name varchar2(60) not null
   , is_territory varchar2(1) not null
   , census_region_code varchar2(3) not null
   , census_region_name varchar2(40) not null
   , census_division_code varchar2(3) not null
   , census_division_name varchar2(40) not null
   , constraint dim_geography_pk primary key (state_code)
   , constraint dim_geography_state_fips_uk unique (state_fips)
   , constraint dim_geography_is_territory_ck check (is_territory in ('Y', 'N'))
);

-- noqa: disable=LT05
comment on table dim_geography is 'DIM: one row per state, district, or territory: 50 states, DC, and 6 territories. Property State is a two-letter code (User Guide p.7). Full Census reference set, independent of sample coverage. Sources: Census state.txt and state-geocodes-v2023.xlsx.';
comment on column dim_geography.state_code is 'Two-letter USPS state code, e.g. CA; foreign key target for dim_loan.property_state';
comment on column dim_geography.state_fips is 'Two-digit state FIPS code, e.g. 06; STATE in Census state.txt';
comment on column dim_geography.state_name is 'State name, e.g. California; STATE_NAME in Census state.txt';
comment on column dim_geography.is_territory is 'Territory flag: Y/N. The 50 states and DC are N.';
comment on column dim_geography.census_region_code is 'Census region code, 1-4; territories use N/A';
comment on column dim_geography.census_region_name is 'Census region: Northeast, Midwest, South, West; territories use Not in a Census region';
comment on column dim_geography.census_division_code is 'Census division code, 1-9; territories use N/A';
comment on column dim_geography.census_division_name is 'Census division, e.g. Pacific; territories use Not in a Census division';
-- noqa: enable=LT05
