-- Load numeric statuses and the two non-numeric statuses. See metric definitions.
merge into dim_delinquency_status t
using (
   with
   nums as (
      select level - 1 as n
      from dual
      connect by level <= 100
   )

   select
      lpad(n, 2, '0') as status_code
      , case when n >= 2 then 'Y' else 'N' end as is_dlq60
   from nums
   union all
   select
      'RA' as status_code
      , 'Y' as is_dlq60
   from dual
   union all
   select
      'XX' as status_code
      , 'N' as is_dlq60
   from dual
) s
   on (t.status_code = s.status_code)
when matched then
   update set
      is_dlq60 = s.is_dlq60
when not matched then
   insert (status_code, is_dlq60)
   values (s.status_code, s.is_dlq60);

commit;
