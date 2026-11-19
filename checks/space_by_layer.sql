-- Name: space_by_layer.sql
-- Purpose: show the space the current account's tables use, grouped by warehouse layer; indexes and LOBs count with their table.
-- Usage: scripts/run_sql.sh checks/space_by_layer.sql (and ORACLE_USER=loan_oltp for the review database)
-- Requires: nothing besides the account's own objects; read-only
-- Called by: scripts/run_end_to_end.sh, and by hand after a load

set pagesize 100
column layer_name heading LAYER format a12
column mib format 999,990.0

with

owner_table as (
   select
      s.bytes
      , coalesce(i.table_name, l.table_name, s.segment_name) as table_name
   from user_segments s
   left join user_indexes i
      on s.segment_name = i.index_name
   left join user_lobs l
      on s.segment_name = l.segment_name or s.segment_name = l.index_name
)

, by_layer as (
   select
      bytes
      , case
         when table_name like 'ODS\_%' escape '\' then 'ODS'
         when table_name like 'DIM\_%' escape '\' then 'DIM'
         when table_name like 'DWD\_%' escape '\' then 'DWD'
         when table_name like 'DWS\_%' escape '\' then 'DWS'
         when table_name like 'ADS\_%' escape '\' then 'ADS'
         when table_name like 'DQ\_%' escape '\' then 'QUALITY'
         when table_name like 'REVIEW\_%' escape '\' or table_name like 'RISK\_%' escape '\'
            or table_name like 'CASE\_%' escape '\' then 'REVIEW'
         else 'OTHER'
      end as layer
   from owner_table
)

select
   case when grouping(layer) = 1 then 'TOTAL' else layer end as layer_name
   , round(sum(bytes) / 1048576, 1) as mib
from by_layer
group by rollup(layer)
order by grouping(layer), layer;
