-- First warehouse path; source definitions and calculations are documented in docs/metric_definitions.md.

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
-- noqa: enable=LT05
