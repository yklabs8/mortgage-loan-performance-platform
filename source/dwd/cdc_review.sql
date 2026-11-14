-- Name: cdc_review.sql
-- Purpose: create the procedure cdc_review, which extracts changes in the OLTP review system into the warehouse by timestamp (timestamp-based CDC).
--          1. Case statuses and review rules are fully synced; the user dimension appends SCD2 versions by CDC observation time
--          2. Cases: read cases whose updated_at falls in (lower, upper], recompute their accumulating snapshot, and merge into dwd_review_case
--          3. Status changes: read history rows whose changed_at falls in the same range and insert only those not yet in dwd_review_case_event
--          4. Record this run's start and end watermark and row counts (etl_cdc_run); the new watermark = upper bound
--          Range: lower = previous watermark - overlap window (default 10 minutes), upper = database time when this run starts. Three guards against missed rows:
--          - The watermark is "the time this run started", not "the largest timestamp read": the latter misses rows when the same timestamp still has uncommitted rows
--          - updated_at is the moment of modification, not of commit: a row changed at 10:00 but committed at 10:05 is invisible to the 10:03 run,
--            and the next run, reading from "watermark - 10 minutes", picks it up. The overlap window must be longer than the longest transaction
--          - Rows in the overlap window are read twice, so writes use merge (by case ID and history ID) and give the same result however often they are read
--          Deletes: OLTP has no path that deletes a case (review_api has none and foreign keys forbid it), so deletes are not captured;
--          if someone deleted rows directly, the reconciliation in checks/dq_review_cdc.sql would notice (OLTP and warehouse case counts differ)
--          Data is changed only through the review service: assigning, adding a note, and deciding all update the case row (and its updated_at),
--          so cases only need risk_review_case.updated_at
--          Does not commit; the caller commits (source/dwd/run_cdc_review.sql), so tests can roll back
-- Requires: etl_watermark, etl_cdc_run, dwd_review_case, dwd_review_case_event, dim_case_status, dim_review_user,
--           load_dim_review_user, dim_review_rule (load_dim_review_rule), dim_loan_key_map, dim_date; the OLTP tables
-- Called by: source/dwd/run_cdc_review.sql; test/test_review_cdc.sql

create or replace procedure cdc_review(
   in_overlap_minutes in number default 10
) is
   l_to timestamp(6) := systimestamp;  -- upper bound: database time when this run starts
   l_case_from timestamp(6);
   l_event_from timestamp(6);
   l_changed_cases pls_integer;
   l_merged_cases pls_integer;
   l_event_rows pls_integer;
   l_event_loaded pls_integer;

   -- Lower bound of a source: previous watermark - overlap window; with no watermark yet, read from a very early time (full extract)
   function lower_bound(in_source in varchar2) return timestamp is
      l_watermark timestamp(6);
   begin
      select max(watermark_ts)
      into l_watermark
      from etl_watermark
      where source_name = in_source;
      return coalesce(l_watermark, timestamp '1900-01-01 00:00:00')
      - numtodsinterval(in_overlap_minutes, 'MINUTE');
   end lower_bound;

   -- Record this extraction and move the watermark to the upper bound
   procedure record_run(
      in_source in varchar2
      , in_from in timestamp
      , in_rows in pls_integer
      , in_staged in pls_integer
      , in_loaded in pls_integer
   ) is
   begin
      insert into etl_cdc_run (
         source_name, overlap_minutes, from_ts, to_ts
         , extracted_rows, staged_rows, loaded_rows
      )
      values (
         in_source, in_overlap_minutes, in_from, l_to
         , in_rows, in_staged, in_loaded
      );
      merge into etl_watermark t
      using (
         select
            in_source as source_name
            , l_to as watermark_ts
         from dual
      ) s
         on (t.source_name = s.source_name)
      when matched then
         update set watermark_ts = s.watermark_ts
      when not matched then
         insert (source_name, watermark_ts)
         values (s.source_name, s.watermark_ts);
   end record_run;
begin
   if in_overlap_minutes is null or in_overlap_minutes < 0 then
      raise_application_error(-20041, 'Overlap window must not be empty or negative');
   end if;

   -- 1. Full sync of the dimensions (all small)
   load_dim_review_rule;
   merge into dim_case_status t
   using (
      select
         status_code
         , status_name
         , is_terminal
      from loan_oltp.case_status
   ) s
      on (t.status_code = s.status_code)
   when matched then
      update set
         status_name = s.status_name
         , is_terminal = s.is_terminal
   when not matched then
      insert (status_code, status_name, is_terminal)
      values (s.status_code, s.status_name, s.is_terminal);

   load_dim_review_user(systimestamp);

   -- 2. Cases: recompute the whole snapshot row of each case changed in this range
   l_case_from := lower_bound('REVIEW_CASE');
   select count(*)
   into l_changed_cases
   from loan_oltp.risk_review_case
   where updated_at > l_case_from and updated_at <= l_to;

   merge into dwd_review_case t
   using (
      with

      win as (
         select
            l_case_from as from_ts
            , l_to as to_ts
         from dual
      )

      , changed as (
         select
            rrc.case_id
            , rrc.case_number
            , rrc.candidate_id
            , rrc.current_status
            , rrc.opened_by_user_id
            , rrc.opened_at
            , rrc.closed_at
            , rrc.updated_at
         from loan_oltp.risk_review_case rrc
         cross join win w
         where rrc.updated_at > w.from_ts and rrc.updated_at <= w.to_ts
      )

      -- Assignments: time of the first assignment; latest assignee
      , assign_ranked as (
         select
            ca.case_id
            , ca.assigned_at
            , ca.assignee_user_id
            , min(ca.assigned_at) over (partition by ca.case_id)
               as first_assigned_at
            , row_number() over (
               partition by ca.case_id
               order by ca.assigned_at desc, ca.assignment_id desc
            ) as rn
         from loan_oltp.case_assignment ca
         inner join changed ch
            on ca.case_id = ch.case_id
      )

      -- Status history: first entry into review, ever escalated or reopened, number of changes
      , hist as (
         select
            csh.case_id
            , min(
               case when csh.to_status = 'IN_REVIEW' then csh.changed_at end
            ) as first_in_review_at
            , max(case when csh.to_status = 'ESCALATED' then 'Y' else 'N' end)
               as was_escalated
            , max(case
               when csh.from_status = 'CLOSED' then 'Y' else 'N'
            end) as was_reopened
            , count(*) as status_change_count
         from loan_oltp.case_status_history csh
         inner join changed ch
            on csh.case_id = ch.case_id
         group by csh.case_id
      )

      -- Decisions: time and type of the latest one
      , decision_ranked as (
         select
            rd.case_id
            , rd.decided_at
            , rd.decision_type
            , row_number() over (
               partition by rd.case_id
               order by rd.decided_at desc, rd.decision_id desc
            ) as rn
         from loan_oltp.review_decision rd
         inner join changed ch
            on rd.case_id = ch.case_id
      )

      , annotations as (
         select
            can.case_id
            , count(*) as annotation_count
         from loan_oltp.case_annotation can
         inner join changed ch
            on can.case_id = ch.case_id
         group by can.case_id
      )

      select
         ch.case_id
         , ch.case_number
         , ch.candidate_id
         , drr.rule_version_key
         , rcd.data_source
         , rcd.loan_identifier
         , km.loan_durable_key
         , rcd.reporting_month
         , to_number(to_char(rcd.reporting_month, 'YYYYMMDD'))
            as reporting_date_key
         , rcd.source_release_id
         , ch.current_status
         , ch.opened_by_user_id
         , ar.assignee_user_id as current_assignee_user_id
         , ch.opened_at
         , to_number(to_char(ch.opened_at, 'YYYYMMDD')) as opened_date_key
         , ar.first_assigned_at
         , h.first_in_review_at
         , dr.decided_at as last_decided_at
         , dr.decision_type as last_decision_type
         , ch.closed_at
         , to_number(to_char(ch.closed_at, 'YYYYMMDD')) as closed_date_key
         , coalesce(h.was_escalated, 'N') as was_escalated
         , coalesce(h.was_reopened, 'N') as was_reopened
         , coalesce(h.status_change_count, 0) as status_change_count
         , coalesce(an.annotation_count, 0) as annotation_count
         , ch.updated_at as source_updated_at
      from changed ch
      inner join loan_oltp.review_candidate rcd
         on ch.candidate_id = rcd.candidate_id
      inner join dim_review_rule drr
         on rcd.rule_version_id = drr.rule_version_id
      inner join dim_loan_key_map km
         on
            rcd.data_source = km.data_source
            and rcd.loan_identifier = km.loan_identifier
      left join assign_ranked ar
         on ch.case_id = ar.case_id and ar.rn = 1
      left join hist h
         on ch.case_id = h.case_id
      left join decision_ranked dr
         on ch.case_id = dr.case_id and dr.rn = 1
      left join annotations an
         on ch.case_id = an.case_id
   ) s
      on (t.case_id = s.case_id)
   when matched then
      update set
         case_number = s.case_number
         , candidate_id = s.candidate_id
         , rule_version_key = s.rule_version_key
         , data_source = s.data_source
         , loan_identifier = s.loan_identifier
         , loan_durable_key = s.loan_durable_key
         , reporting_month = s.reporting_month
         , reporting_date_key = s.reporting_date_key
         , source_release_id = s.source_release_id
         , current_status = s.current_status
         , opened_by_user_id = s.opened_by_user_id
         , current_assignee_user_id = s.current_assignee_user_id
         , opened_at = s.opened_at
         , opened_date_key = s.opened_date_key
         , first_assigned_at = s.first_assigned_at
         , first_in_review_at = s.first_in_review_at
         , last_decided_at = s.last_decided_at
         , last_decision_type = s.last_decision_type
         , closed_at = s.closed_at
         , closed_date_key = s.closed_date_key
         , was_escalated = s.was_escalated
         , was_reopened = s.was_reopened
         , status_change_count = s.status_change_count
         , annotation_count = s.annotation_count
         , source_updated_at = s.source_updated_at
   when not matched then
      insert (
         case_id, case_number, candidate_id, rule_version_key, data_source
         , loan_identifier, loan_durable_key, reporting_month
         , reporting_date_key, source_release_id, current_status
         , opened_by_user_id, current_assignee_user_id, opened_at
         , opened_date_key, first_assigned_at, first_in_review_at
         , last_decided_at, last_decision_type, closed_at, closed_date_key
         , was_escalated, was_reopened, status_change_count, annotation_count
         , source_updated_at
      )
      values (
         s.case_id, s.case_number, s.candidate_id, s.rule_version_key
         , s.data_source, s.loan_identifier, s.loan_durable_key
         , s.reporting_month, s.reporting_date_key, s.source_release_id
         , s.current_status, s.opened_by_user_id, s.current_assignee_user_id
         , s.opened_at, s.opened_date_key, s.first_assigned_at
         , s.first_in_review_at, s.last_decided_at, s.last_decision_type
         , s.closed_at, s.closed_date_key, s.was_escalated, s.was_reopened
         , s.status_change_count, s.annotation_count, s.source_updated_at
      );
   l_merged_cases := sql%rowcount;

   -- Count reconciliation: every changed case must be written (an inner join that misses a dimension would drop rows, which must fail rather than be lost silently)
   if l_merged_cases != l_changed_cases then
      raise_application_error(
         -20042
         , 'Case mismatch: ' || l_changed_cases || ' changed, '
         || l_merged_cases || ' written to the warehouse (missing in the rule or loan dimension?)'
      );
   end if;
   record_run(
      'REVIEW_CASE', l_case_from, l_changed_cases
      , l_merged_cases, l_merged_cases
   );

   -- 3. Status changes: append-only, insert only rows not already present (overlap re-reads are already there)
   l_event_from := lower_bound('REVIEW_CASE_EVENT');
   select count(*)
   into l_event_rows
   from loan_oltp.case_status_history
   where changed_at > l_event_from and changed_at <= l_to;

   merge into dwd_review_case_event t
   using (
      with win as (
         select
            l_event_from as from_ts
            , l_to as to_ts
         from dual
      )

      select
         csh.status_event_id
         , csh.case_id
         , csh.from_status
         , csh.to_status
         , csh.changed_by_user_id
         , csh.changed_at
         , to_number(to_char(csh.changed_at, 'YYYYMMDD')) as changed_date_key
      from loan_oltp.case_status_history csh
      cross join win w
      where csh.changed_at > w.from_ts and csh.changed_at <= w.to_ts
   ) s
      on (t.status_event_id = s.status_event_id)
   when not matched then
      insert (
         status_event_id, case_id, from_status, to_status
         , changed_by_user_id, changed_at, changed_date_key
      )
      values (
         s.status_event_id, s.case_id, s.from_status, s.to_status
         , s.changed_by_user_id, s.changed_at, s.changed_date_key
      );
   -- The overlap window re-reads old events, so written rows can be fewer than extracted rows; check that every event key exists in the target instead.
   with win as (
      select
         l_event_from as from_ts
         , l_to as to_ts
      from dual
   )

   select count(*)
   into l_event_loaded
   from loan_oltp.case_status_history h
   inner join dwd_review_case_event e
      on h.status_event_id = e.status_event_id
   cross join win w
   where h.changed_at > w.from_ts and h.changed_at <= w.to_ts;
   if l_event_loaded != l_event_rows then
      raise_application_error(-20044, 'Some extracted CDC status events were not written to the warehouse');
   end if;
   record_run(
      'REVIEW_CASE_EVENT', l_event_from, l_event_rows
      , l_event_rows, l_event_loaded
   );
end cdc_review;
/
