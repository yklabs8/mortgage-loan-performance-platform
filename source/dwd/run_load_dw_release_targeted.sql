-- run_load_dw_release_targeted.sql
-- Run load dw release targeted. See docs/metric_definitions.md for analytical definitions.
begin
   load_dw_release('&release_id', '&base_release_id');
end;
/

select
   change_kind
   , count(*) as loans
from dw_recompute_loan
where release_id = '&release_id'
group by change_kind
order by change_kind asc;
