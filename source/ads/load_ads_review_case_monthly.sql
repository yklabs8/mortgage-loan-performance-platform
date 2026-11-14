-- Name: load_ads_review_case_monthly.sql
-- Purpose: compute the monthly report from the accumulating case snapshot dwd_review_case, delete-and-insert the whole table (cases are few, increments are not worth it);
--          does not commit; the caller commits (in the same transaction as the extraction in source/dwd/run_cdc_review.sql)
-- Note: the layering convention keeps ADS from reading DWD where possible. Here it reads dwd_review_case directly:
--       it already is a one-row-per-case accumulating snapshot, and another one-row-per-case summary table would only copy it
-- Requires: dwd_review_case, dim_review_rule, ads_review_case_monthly exist
-- Called by: source/dwd/run_cdc_review.sql; test/test_ads_review_case_monthly.sql

create or replace procedure load_ads_review_case_monthly is
   l_missing_close pls_integer;
begin
   select count(*) into l_missing_close
   from dwd_review_case drc
   where
      drc.closed_at is not null
      and not exists (
         select 1 from dwd_review_case_event ev
         where ev.case_id = drc.case_id and ev.to_status = 'CLOSED'
      );
   if l_missing_close > 0 then
      raise_application_error(-20081, 'A closed case is missing its close status event');
   end if;

   delete from ads_review_case_monthly;

   insert into ads_review_case_monthly (
      opened_month
      , data_source
      , rule_code
      , current_status
      , case_count
      , escalated_count
      , reopened_count
      , closed_count
      , total_days_to_close
      , refreshed_at
   )
   with

   -- One row per case: opening month, rule, reopen flag, currently closed, days to first close
   first_close as (
      select
         case_id
         , min(changed_at) as first_closed_at
      from dwd_review_case_event
      where to_status = 'CLOSED'
      group by case_id
   )
   ,
   cases as (
      select
         trunc(drc.opened_at, 'mm') as opened_month
         , drc.data_source
         , drr.rule_code
         , drc.current_status
         , case when drc.was_escalated = 'Y' then 1 else 0 end as escalated
         , case when drc.was_reopened = 'Y' then 1 else 0 end as reopened
         , case when drc.closed_at is not null then 1 else 0 end as closed
         -- Subtracting two timestamps gives an interval, converted to (fractional) days
         , case
            when drc.closed_at is not null and fc.first_closed_at is not null
               then
                  extract(day from (fc.first_closed_at - drc.opened_at))
                  + extract(hour from (fc.first_closed_at - drc.opened_at)) / 24
                  + extract(minute from (fc.first_closed_at - drc.opened_at))
                  / 1440
                  + extract(second from (fc.first_closed_at - drc.opened_at))
                  / 86400
            else 0
         end as days_to_close
      from dwd_review_case drc
      inner join dim_review_rule drr
         on drc.rule_version_key = drr.rule_version_key
      left join first_close fc on drc.case_id = fc.case_id
   )

   select
      opened_month
      , data_source
      , rule_code
      , current_status
      , count(*) as case_count
      , sum(escalated) as escalated_count
      , sum(reopened) as reopened_count
      , sum(closed) as closed_count
      , sum(days_to_close) as total_days_to_close
      , systimestamp as refreshed_at
   from cases
   group by
      opened_month
      , data_source
      , rule_code
      , current_status;
end load_ads_review_case_monthly;
/
