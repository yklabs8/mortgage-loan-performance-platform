-- load_dim_geography.sql
-- Reference data: https://www2.census.gov/geo/docs/reference/state.txt and https://www2.census.gov/programs-surveys/popest/geographies/2023/state-geocodes-v2023.xlsx . Join by FIPS; territories use N/A for region and division.
merge into dim_geography t
using (
   select
      'AL' as state_code
      , '01' as state_fips
      , 'Alabama' as state_name
      , 'N' as is_territory
      , '3' as census_region_code
      , 'South' as census_region_name
      , '6' as census_division_code
      , 'East South Central' as census_division_name
   from dual
   union all
   select
      'AK' as state_code
      , '02' as state_fips
      , 'Alaska' as state_name
      , 'N' as is_territory
      , '4' as census_region_code
      , 'West' as census_region_name
      , '9' as census_division_code
      , 'Pacific' as census_division_name
   from dual
   union all
   select
      'AZ' as state_code
      , '04' as state_fips
      , 'Arizona' as state_name
      , 'N' as is_territory
      , '4' as census_region_code
      , 'West' as census_region_name
      , '8' as census_division_code
      , 'Mountain' as census_division_name
   from dual
   union all
   select
      'AR' as state_code
      , '05' as state_fips
      , 'Arkansas' as state_name
      , 'N' as is_territory
      , '3' as census_region_code
      , 'South' as census_region_name
      , '7' as census_division_code
      , 'West South Central' as census_division_name
   from dual
   union all
   select
      'CA' as state_code
      , '06' as state_fips
      , 'California' as state_name
      , 'N' as is_territory
      , '4' as census_region_code
      , 'West' as census_region_name
      , '9' as census_division_code
      , 'Pacific' as census_division_name
   from dual
   union all
   select
      'CO' as state_code
      , '08' as state_fips
      , 'Colorado' as state_name
      , 'N' as is_territory
      , '4' as census_region_code
      , 'West' as census_region_name
      , '8' as census_division_code
      , 'Mountain' as census_division_name
   from dual
   union all
   select
      'CT' as state_code
      , '09' as state_fips
      , 'Connecticut' as state_name
      , 'N' as is_territory
      , '1' as census_region_code
      , 'Northeast' as census_region_name
      , '1' as census_division_code
      , 'New England' as census_division_name
   from dual
   union all
   select
      'DE' as state_code
      , '10' as state_fips
      , 'Delaware' as state_name
      , 'N' as is_territory
      , '3' as census_region_code
      , 'South' as census_region_name
      , '5' as census_division_code
      , 'South Atlantic' as census_division_name
   from dual
   union all
   select
      'DC' as state_code
      , '11' as state_fips
      , 'District of Columbia' as state_name
      , 'N' as is_territory
      , '3' as census_region_code
      , 'South' as census_region_name
      , '5' as census_division_code
      , 'South Atlantic' as census_division_name
   from dual
   union all
   select
      'FL' as state_code
      , '12' as state_fips
      , 'Florida' as state_name
      , 'N' as is_territory
      , '3' as census_region_code
      , 'South' as census_region_name
      , '5' as census_division_code
      , 'South Atlantic' as census_division_name
   from dual
   union all
   select
      'GA' as state_code
      , '13' as state_fips
      , 'Georgia' as state_name
      , 'N' as is_territory
      , '3' as census_region_code
      , 'South' as census_region_name
      , '5' as census_division_code
      , 'South Atlantic' as census_division_name
   from dual
   union all
   select
      'HI' as state_code
      , '15' as state_fips
      , 'Hawaii' as state_name
      , 'N' as is_territory
      , '4' as census_region_code
      , 'West' as census_region_name
      , '9' as census_division_code
      , 'Pacific' as census_division_name
   from dual
   union all
   select
      'ID' as state_code
      , '16' as state_fips
      , 'Idaho' as state_name
      , 'N' as is_territory
      , '4' as census_region_code
      , 'West' as census_region_name
      , '8' as census_division_code
      , 'Mountain' as census_division_name
   from dual
   union all
   select
      'IL' as state_code
      , '17' as state_fips
      , 'Illinois' as state_name
      , 'N' as is_territory
      , '2' as census_region_code
      , 'Midwest' as census_region_name
      , '3' as census_division_code
      , 'East North Central' as census_division_name
   from dual
   union all
   select
      'IN' as state_code
      , '18' as state_fips
      , 'Indiana' as state_name
      , 'N' as is_territory
      , '2' as census_region_code
      , 'Midwest' as census_region_name
      , '3' as census_division_code
      , 'East North Central' as census_division_name
   from dual
   union all
   select
      'IA' as state_code
      , '19' as state_fips
      , 'Iowa' as state_name
      , 'N' as is_territory
      , '2' as census_region_code
      , 'Midwest' as census_region_name
      , '4' as census_division_code
      , 'West North Central' as census_division_name
   from dual
   union all
   select
      'KS' as state_code
      , '20' as state_fips
      , 'Kansas' as state_name
      , 'N' as is_territory
      , '2' as census_region_code
      , 'Midwest' as census_region_name
      , '4' as census_division_code
      , 'West North Central' as census_division_name
   from dual
   union all
   select
      'KY' as state_code
      , '21' as state_fips
      , 'Kentucky' as state_name
      , 'N' as is_territory
      , '3' as census_region_code
      , 'South' as census_region_name
      , '6' as census_division_code
      , 'East South Central' as census_division_name
   from dual
   union all
   select
      'LA' as state_code
      , '22' as state_fips
      , 'Louisiana' as state_name
      , 'N' as is_territory
      , '3' as census_region_code
      , 'South' as census_region_name
      , '7' as census_division_code
      , 'West South Central' as census_division_name
   from dual
   union all
   select
      'ME' as state_code
      , '23' as state_fips
      , 'Maine' as state_name
      , 'N' as is_territory
      , '1' as census_region_code
      , 'Northeast' as census_region_name
      , '1' as census_division_code
      , 'New England' as census_division_name
   from dual
   union all
   select
      'MD' as state_code
      , '24' as state_fips
      , 'Maryland' as state_name
      , 'N' as is_territory
      , '3' as census_region_code
      , 'South' as census_region_name
      , '5' as census_division_code
      , 'South Atlantic' as census_division_name
   from dual
   union all
   select
      'MA' as state_code
      , '25' as state_fips
      , 'Massachusetts' as state_name
      , 'N' as is_territory
      , '1' as census_region_code
      , 'Northeast' as census_region_name
      , '1' as census_division_code
      , 'New England' as census_division_name
   from dual
   union all
   select
      'MI' as state_code
      , '26' as state_fips
      , 'Michigan' as state_name
      , 'N' as is_territory
      , '2' as census_region_code
      , 'Midwest' as census_region_name
      , '3' as census_division_code
      , 'East North Central' as census_division_name
   from dual
   union all
   select
      'MN' as state_code
      , '27' as state_fips
      , 'Minnesota' as state_name
      , 'N' as is_territory
      , '2' as census_region_code
      , 'Midwest' as census_region_name
      , '4' as census_division_code
      , 'West North Central' as census_division_name
   from dual
   union all
   select
      'MS' as state_code
      , '28' as state_fips
      , 'Mississippi' as state_name
      , 'N' as is_territory
      , '3' as census_region_code
      , 'South' as census_region_name
      , '6' as census_division_code
      , 'East South Central' as census_division_name
   from dual
   union all
   select
      'MO' as state_code
      , '29' as state_fips
      , 'Missouri' as state_name
      , 'N' as is_territory
      , '2' as census_region_code
      , 'Midwest' as census_region_name
      , '4' as census_division_code
      , 'West North Central' as census_division_name
   from dual
   union all
   select
      'MT' as state_code
      , '30' as state_fips
      , 'Montana' as state_name
      , 'N' as is_territory
      , '4' as census_region_code
      , 'West' as census_region_name
      , '8' as census_division_code
      , 'Mountain' as census_division_name
   from dual
   union all
   select
      'NE' as state_code
      , '31' as state_fips
      , 'Nebraska' as state_name
      , 'N' as is_territory
      , '2' as census_region_code
      , 'Midwest' as census_region_name
      , '4' as census_division_code
      , 'West North Central' as census_division_name
   from dual
   union all
   select
      'NV' as state_code
      , '32' as state_fips
      , 'Nevada' as state_name
      , 'N' as is_territory
      , '4' as census_region_code
      , 'West' as census_region_name
      , '8' as census_division_code
      , 'Mountain' as census_division_name
   from dual
   union all
   select
      'NH' as state_code
      , '33' as state_fips
      , 'New Hampshire' as state_name
      , 'N' as is_territory
      , '1' as census_region_code
      , 'Northeast' as census_region_name
      , '1' as census_division_code
      , 'New England' as census_division_name
   from dual
   union all
   select
      'NJ' as state_code
      , '34' as state_fips
      , 'New Jersey' as state_name
      , 'N' as is_territory
      , '1' as census_region_code
      , 'Northeast' as census_region_name
      , '2' as census_division_code
      , 'Middle Atlantic' as census_division_name
   from dual
   union all
   select
      'NM' as state_code
      , '35' as state_fips
      , 'New Mexico' as state_name
      , 'N' as is_territory
      , '4' as census_region_code
      , 'West' as census_region_name
      , '8' as census_division_code
      , 'Mountain' as census_division_name
   from dual
   union all
   select
      'NY' as state_code
      , '36' as state_fips
      , 'New York' as state_name
      , 'N' as is_territory
      , '1' as census_region_code
      , 'Northeast' as census_region_name
      , '2' as census_division_code
      , 'Middle Atlantic' as census_division_name
   from dual
   union all
   select
      'NC' as state_code
      , '37' as state_fips
      , 'North Carolina' as state_name
      , 'N' as is_territory
      , '3' as census_region_code
      , 'South' as census_region_name
      , '5' as census_division_code
      , 'South Atlantic' as census_division_name
   from dual
   union all
   select
      'ND' as state_code
      , '38' as state_fips
      , 'North Dakota' as state_name
      , 'N' as is_territory
      , '2' as census_region_code
      , 'Midwest' as census_region_name
      , '4' as census_division_code
      , 'West North Central' as census_division_name
   from dual
   union all
   select
      'OH' as state_code
      , '39' as state_fips
      , 'Ohio' as state_name
      , 'N' as is_territory
      , '2' as census_region_code
      , 'Midwest' as census_region_name
      , '3' as census_division_code
      , 'East North Central' as census_division_name
   from dual
   union all
   select
      'OK' as state_code
      , '40' as state_fips
      , 'Oklahoma' as state_name
      , 'N' as is_territory
      , '3' as census_region_code
      , 'South' as census_region_name
      , '7' as census_division_code
      , 'West South Central' as census_division_name
   from dual
   union all
   select
      'OR' as state_code
      , '41' as state_fips
      , 'Oregon' as state_name
      , 'N' as is_territory
      , '4' as census_region_code
      , 'West' as census_region_name
      , '9' as census_division_code
      , 'Pacific' as census_division_name
   from dual
   union all
   select
      'PA' as state_code
      , '42' as state_fips
      , 'Pennsylvania' as state_name
      , 'N' as is_territory
      , '1' as census_region_code
      , 'Northeast' as census_region_name
      , '2' as census_division_code
      , 'Middle Atlantic' as census_division_name
   from dual
   union all
   select
      'RI' as state_code
      , '44' as state_fips
      , 'Rhode Island' as state_name
      , 'N' as is_territory
      , '1' as census_region_code
      , 'Northeast' as census_region_name
      , '1' as census_division_code
      , 'New England' as census_division_name
   from dual
   union all
   select
      'SC' as state_code
      , '45' as state_fips
      , 'South Carolina' as state_name
      , 'N' as is_territory
      , '3' as census_region_code
      , 'South' as census_region_name
      , '5' as census_division_code
      , 'South Atlantic' as census_division_name
   from dual
   union all
   select
      'SD' as state_code
      , '46' as state_fips
      , 'South Dakota' as state_name
      , 'N' as is_territory
      , '2' as census_region_code
      , 'Midwest' as census_region_name
      , '4' as census_division_code
      , 'West North Central' as census_division_name
   from dual
   union all
   select
      'TN' as state_code
      , '47' as state_fips
      , 'Tennessee' as state_name
      , 'N' as is_territory
      , '3' as census_region_code
      , 'South' as census_region_name
      , '6' as census_division_code
      , 'East South Central' as census_division_name
   from dual
   union all
   select
      'TX' as state_code
      , '48' as state_fips
      , 'Texas' as state_name
      , 'N' as is_territory
      , '3' as census_region_code
      , 'South' as census_region_name
      , '7' as census_division_code
      , 'West South Central' as census_division_name
   from dual
   union all
   select
      'UT' as state_code
      , '49' as state_fips
      , 'Utah' as state_name
      , 'N' as is_territory
      , '4' as census_region_code
      , 'West' as census_region_name
      , '8' as census_division_code
      , 'Mountain' as census_division_name
   from dual
   union all
   select
      'VT' as state_code
      , '50' as state_fips
      , 'Vermont' as state_name
      , 'N' as is_territory
      , '1' as census_region_code
      , 'Northeast' as census_region_name
      , '1' as census_division_code
      , 'New England' as census_division_name
   from dual
   union all
   select
      'VA' as state_code
      , '51' as state_fips
      , 'Virginia' as state_name
      , 'N' as is_territory
      , '3' as census_region_code
      , 'South' as census_region_name
      , '5' as census_division_code
      , 'South Atlantic' as census_division_name
   from dual
   union all
   select
      'WA' as state_code
      , '53' as state_fips
      , 'Washington' as state_name
      , 'N' as is_territory
      , '4' as census_region_code
      , 'West' as census_region_name
      , '9' as census_division_code
      , 'Pacific' as census_division_name
   from dual
   union all
   select
      'WV' as state_code
      , '54' as state_fips
      , 'West Virginia' as state_name
      , 'N' as is_territory
      , '3' as census_region_code
      , 'South' as census_region_name
      , '5' as census_division_code
      , 'South Atlantic' as census_division_name
   from dual
   union all
   select
      'WI' as state_code
      , '55' as state_fips
      , 'Wisconsin' as state_name
      , 'N' as is_territory
      , '2' as census_region_code
      , 'Midwest' as census_region_name
      , '3' as census_division_code
      , 'East North Central' as census_division_name
   from dual
   union all
   select
      'WY' as state_code
      , '56' as state_fips
      , 'Wyoming' as state_name
      , 'N' as is_territory
      , '4' as census_region_code
      , 'West' as census_region_name
      , '8' as census_division_code
      , 'Mountain' as census_division_name
   from dual
   union all
   select
      'AS' as state_code
      , '60' as state_fips
      , 'American Samoa' as state_name
      , 'Y' as is_territory
      , 'N/A' as census_region_code
      , 'Not in a Census region' as census_region_name
      , 'N/A' as census_division_code
      , 'Not in a Census division' as census_division_name
   from dual
   union all
   select
      'GU' as state_code
      , '66' as state_fips
      , 'Guam' as state_name
      , 'Y' as is_territory
      , 'N/A' as census_region_code
      , 'Not in a Census region' as census_region_name
      , 'N/A' as census_division_code
      , 'Not in a Census division' as census_division_name
   from dual
   union all
   select
      'MP' as state_code
      , '69' as state_fips
      , 'Northern Mariana Islands' as state_name
      , 'Y' as is_territory
      , 'N/A' as census_region_code
      , 'Not in a Census region' as census_region_name
      , 'N/A' as census_division_code
      , 'Not in a Census division' as census_division_name
   from dual
   union all
   select
      'PR' as state_code
      , '72' as state_fips
      , 'Puerto Rico' as state_name
      , 'Y' as is_territory
      , 'N/A' as census_region_code
      , 'Not in a Census region' as census_region_name
      , 'N/A' as census_division_code
      , 'Not in a Census division' as census_division_name
   from dual
   union all
   select
      'UM' as state_code
      , '74' as state_fips
      , 'U.S. Minor Outlying Islands' as state_name
      , 'Y' as is_territory
      , 'N/A' as census_region_code
      , 'Not in a Census region' as census_region_name
      , 'N/A' as census_division_code
      , 'Not in a Census division' as census_division_name
   from dual
   union all
   select
      'VI' as state_code
      , '78' as state_fips
      , 'U.S. Virgin Islands' as state_name
      , 'Y' as is_territory
      , 'N/A' as census_region_code
      , 'Not in a Census region' as census_region_name
      , 'N/A' as census_division_code
      , 'Not in a Census division' as census_division_name
   from dual
) s
   on (t.state_code = s.state_code)
when matched then
   update set
      state_fips = s.state_fips
      , state_name = s.state_name
      , is_territory = s.is_territory
      , census_region_code = s.census_region_code
      , census_region_name = s.census_region_name
      , census_division_code = s.census_division_code
      , census_division_name = s.census_division_name
when not matched then
   insert (
      state_code, state_fips, state_name, is_territory, census_region_code
      , census_region_name, census_division_code, census_division_name
   )
   values (
      s.state_code, s.state_fips, s.state_name, s.is_territory
      , s.census_region_code, s.census_region_name, s.census_division_code
      , s.census_division_name
   );

commit;
