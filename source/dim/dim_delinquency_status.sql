-- Delinquency status code and the single 60+ classification used by the metric.
create table dim_delinquency_status (
   status_code varchar2(3) not null
   , is_dlq60 varchar2(1) not null
   , constraint dim_delinquency_status_pk primary key (status_code)
   , constraint dim_delinquency_status_dlq60_ck check (is_dlq60 in ('Y', 'N'))
);
