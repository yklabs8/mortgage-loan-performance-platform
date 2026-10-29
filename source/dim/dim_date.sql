-- dim_date.sql
-- Dim date. See docs/metric_definitions.md for analytical definitions.
create table dim_date (
   date_key number(8) not null
   , calendar_date date not null
   , calendar_year number(4) not null
   , calendar_quarter number(1) not null
   , year_quarter varchar2(6) not null
   , calendar_month number(2) not null
   , year_month_num number(6) not null
   , month_name varchar2(9) not null
   , day_of_month number(2) not null
   , day_of_week number(1) not null
   , day_name varchar2(9) not null
   , is_weekend varchar2(1) not null
   , is_month_start varchar2(1) not null
   , is_month_end varchar2(1) not null
   , month_start_date date not null
   , month_end_date date not null
   , constraint dim_date_pk primary key (date_key)
   , constraint dim_date_calendar_date_uk unique (calendar_date)
   , constraint dim_date_is_weekend_ck check (is_weekend in ('Y', 'N'))
   , constraint dim_date_is_month_start_ck check (is_month_start in ('Y', 'N'))
   , constraint dim_date_is_month_end_ck check (is_month_end in ('Y', 'N'))
);

-- noqa: disable=LT05
comment on table dim_date is 'DIM: one row per day, 1999-01-01 through 2099-12-31. Freddie originations start in 1999 (User Guide pp.2,16). The end date allows room for long terms and modifications. YYYYMMDD is a stable integer date key, the meaningful-key exception allowed by Kimball.';
comment on column dim_date.date_key is 'Date key as an integer YYYYMMDD, e.g. 20100101';
comment on column dim_date.calendar_date is 'Calendar date';
comment on column dim_date.calendar_year is 'Calendar year';
comment on column dim_date.calendar_quarter is 'Quarter, 1-4';
comment on column dim_date.year_quarter is 'Year and quarter, e.g. 2010Q1';
comment on column dim_date.calendar_month is 'Month, 1-12';
comment on column dim_date.year_month_num is 'Year and month as integer YYYYMM, e.g. 201001';
comment on column dim_date.month_name is 'English month name, e.g. January';
comment on column dim_date.day_of_month is 'Day of month, 1-31';
comment on column dim_date.day_of_week is 'ISO weekday: Monday=1 through Sunday=7, independent of database language';
comment on column dim_date.day_name is 'English weekday name, e.g. Monday';
comment on column dim_date.is_weekend is 'Saturday or Sunday: Y/N';
comment on column dim_date.is_month_start is 'First day of month: Y/N. Monthly facts reference the first day.';
comment on column dim_date.is_month_end is 'Last day of month: Y/N';
comment on column dim_date.month_start_date is 'First day of the month';
comment on column dim_date.month_end_date is 'Last day of the month';
-- noqa: enable=LT05
