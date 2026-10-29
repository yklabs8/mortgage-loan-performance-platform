-- load_dim_delinquency_status.sql
-- Load dim delinquency status. See docs/metric_definitions.md for analytical definitions.
merge into dim_delinquency_status t
using (
   with

   -- 0, 1, 2, … 99
   nums as (
      select level - 1 as n
      from dual
      connect by level <= 100
   )

   select
      lpad(n, 2, '0') as status_code
      , case
         when n = 0 then 'C'
         when n = 1 then '30'
         when n = 2 then '60'
         when n = 3 then '90'
         else '120+'
      end as dlq_state
      , least(n, 4) as dlq_state_order
      , case when n >= 2 then 'Y' else 'N' end as is_dlq60
   from nums
   union all
   select
      'RA' as status_code
      , 'REO' as dlq_state
      , 5 as dlq_state_order
      , 'Y' as is_dlq60
   from dual
   union all
   select
      'XX' as status_code
      , 'UNK' as dlq_state
      , 9 as dlq_state_order
      , 'N' as is_dlq60
   from dual
) s
   on (t.status_code = s.status_code)
when matched then
   update set
      dlq_state = s.dlq_state
      , dlq_state_order = s.dlq_state_order
      , is_dlq60 = s.is_dlq60
when not matched then
   insert (status_code, dlq_state, dlq_state_order, is_dlq60)
   values (s.status_code, s.dlq_state, s.dlq_state_order, s.is_dlq60);

commit;
