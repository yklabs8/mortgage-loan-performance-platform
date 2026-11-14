-- Name: dq_ods_ready.sql
-- Purpose: expose, per release, only the latest ODS check run that is complete (every current rule ran), passed, and is later than the last load.
-- Requires: dq_run, dq_check_result, dq_issue, dq_quarantine, ods_load_event.
-- Called by: detail loading, warehouse reconciliation, the load entry check.

create or replace view dq_ods_ready_run as
with latest_runs as (
   select
      r.release_id
      , r.run_id
      , r.started_at
      , row_number() over (
         partition by r.release_id order by r.run_id desc
      ) as rn
   from dq_run r
   where r.check_scope = 'ODS'
)

select
   r.release_id
   , r.run_id
from latest_runs r
where
   r.rn = 1
   and r.started_at > coalesce(
      (
         select max(e.loaded_at)
         from ods_load_event e
         where e.release_id = r.release_id
      )
      , timestamp '1900-01-01 00:00:00'
   )
   -- Require DQ017: it is the last result dq_ods.sql writes and the newest rule.
   -- Checking only DQ000 would let an old run from before DQ017 pass, and out-of-range values would be silently rounded into the detail table
   and exists (
      select 1 from dq_check_result c
      where c.run_id = r.run_id and c.rule_id = 'DQ017'
   )
   and not exists (
      select 1 from dq_check_result c
      where
         c.run_id = r.run_id and c.severity = 'HARD'
         and c.bad_count > 0
         and (
            c.rule_id not in ('DQ004', 'DQ006')
            or c.bad_count != (
               select
                  case
                     when c.rule_id = 'DQ004'
                        then count(distinct q.loan_identifier)
                     else count(*)
                  end
               from dq_quarantine q
               inner join dq_issue i on q.issue_id = i.issue_id
               where i.run_id = r.run_id and q.rule_id = c.rule_id
            )
         )
   );

create or replace view dq_ods_quarantine_keys as
select distinct
   r.release_id
   , r.run_id
   , q.source_table
   , q.source_file
   , q.loan_identifier
   , q.raw_period
from dq_ods_ready_run r
inner join dq_issue i on r.run_id = i.run_id
inner join dq_quarantine q on i.issue_id = q.issue_id;

-- noqa: disable=LT05
comment on table dq_ods_ready_run is 'Per release, the latest ODS check run must be complete, passed, and later than the last load';
comment on table dq_ods_quarantine_keys is 'Each quarantined raw row from the latest valid ODS check appears once';
-- noqa: enable=LT05
