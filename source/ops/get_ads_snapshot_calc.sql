-- Select the latest retained successful ADS calculation at a UTC timestamp.
-- A null return means no retained result existed yet at that time.
-- PL/SQL parameters in the join are misread as unqualified columns by SQLFluff.
-- noqa: disable=LT02,LT04,LT14,RF02
create or replace function get_ads_snapshot_calc(
   in_table in varchar2,
   in_release_id in varchar2 default null,
   in_base_release_id in varchar2 default null,
   in_as_of_at in timestamp with time zone default systimestamp
) return number is
   l_table varchar2(40) := upper(in_table);
   l_calc_id number;
begin
   if l_table not in (
      'ADS_VINTAGE_DLQ60_CURVE', 'ADS_DLQ_TRANSITION_MONTHLY',
      'ADS_MODIFICATION_OUTCOME', 'ADS_RELEASE_DIFF_SUMMARY',
      'ADS_RELEASE_DIFF_DETAIL', 'ADS_REVIEW_CASE_MONTHLY'
   ) then
      raise_application_error(-20118, 'ADS table without retained history: ' || in_table);
   end if;
   select max(c.calc_id) keep (
      dense_rank last order by c.published_at, c.calc_id
   ) into l_calc_id
   from dw_calculation c
   inner join dw_ads_snapshot s on c.calc_id = s.calc_id
   where c.output_table = l_table and c.status = 'SUCCESS'
      and coalesce(c.release_id, '~') = coalesce(in_release_id, '~')
      and coalesce(c.base_release_id, '~') = coalesce(in_base_release_id, '~')
      and c.published_at <= in_as_of_at;
   return l_calc_id;
end get_ads_snapshot_calc;
/
