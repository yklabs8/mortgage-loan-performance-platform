-- First warehouse path; source definitions and calculations are documented in docs/metric_definitions.md.

merge into dim_date t
using (
   with

   days as (
      select date '1999-01-01' + level - 1 as d
      from dual
      connect by date '1999-01-01' + level - 1 <= date '2099-12-31'
   )

   select
      to_number(to_char(d, 'yyyymmdd')) as date_key
      , d as calendar_date
      , extract(year from d) as calendar_year
      , to_number(to_char(d, 'q')) as calendar_quarter
      , to_char(d, 'yyyy') || 'Q' || to_char(d, 'q') as year_quarter
      , extract(month from d) as calendar_month
      , to_number(to_char(d, 'yyyymm')) as year_month_num
      , to_char(d, 'fmMonth', 'nls_date_language = english') as month_name
      , extract(day from d) as day_of_month
      , d - trunc(d, 'iw') + 1 as day_of_week
      , to_char(d, 'fmDay', 'nls_date_language = english') as day_name
      , case when d - trunc(d, 'iw') >= 5 then 'Y' else 'N' end as is_weekend
      , case when d = trunc(d, 'mm') then 'Y' else 'N' end as is_month_start
      , case when d = last_day(d) then 'Y' else 'N' end as is_month_end
      , trunc(d, 'mm') as month_start_date
      , last_day(d) as month_end_date
   from days
) s
   on (t.date_key = s.date_key)
when matched then
   update set
      calendar_date = s.calendar_date
      , calendar_year = s.calendar_year
      , calendar_quarter = s.calendar_quarter
      , year_quarter = s.year_quarter
      , calendar_month = s.calendar_month
      , year_month_num = s.year_month_num
      , month_name = s.month_name
      , day_of_month = s.day_of_month
      , day_of_week = s.day_of_week
      , day_name = s.day_name
      , is_weekend = s.is_weekend
      , is_month_start = s.is_month_start
      , is_month_end = s.is_month_end
      , month_start_date = s.month_start_date
      , month_end_date = s.month_end_date
when not matched then
   insert (
      date_key, calendar_date, calendar_year, calendar_quarter, year_quarter
      , calendar_month, year_month_num, month_name, day_of_month, day_of_week
      , day_name, is_weekend, is_month_start, is_month_end, month_start_date
      , month_end_date
   )
   values (
      s.date_key, s.calendar_date, s.calendar_year, s.calendar_quarter
      , s.year_quarter, s.calendar_month, s.year_month_num, s.month_name
      , s.day_of_month, s.day_of_week, s.day_name, s.is_weekend
      , s.is_month_start, s.is_month_end, s.month_start_date
      , s.month_end_date
   );

commit;
