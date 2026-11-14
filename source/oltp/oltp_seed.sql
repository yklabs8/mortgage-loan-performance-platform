-- Name: oltp_seed.sql
-- Purpose: load the risk review system's reference data (roles, case statuses, allowed status changes) and demo data (two demo users,
--          one demo rule). Rows are merged by business key, so reruns create no duplicates
-- Requires: oltp_tables.sql and oltp_triggers.sql have run
-- Called by: scripts/run_sql.sh source/oltp/oltp_seed.sql
-- Note: the demo rule is a demonstration rule, not a real bank policy

merge into app_role t
using (
   select
      'ANALYST' as role_code
      , 'Analyst' as role_name
   from dual
   union all
   select
      'MANAGER' as role_code
      , 'Manager' as role_name
   from dual
) s
   on (t.role_code = s.role_code)
when not matched then
   insert (role_code, role_name) values (s.role_code, s.role_name);

merge into case_status t
using (
   select
      'OPEN' as status_code
      , 'Open' as status_name
      , 'N' as is_terminal
   from dual
   union all
   select
      'ASSIGNED' as status_code
      , 'Assigned' as status_name
      , 'N' as is_terminal
   from dual
   union all
   select
      'IN_REVIEW' as status_code
      , 'In review' as status_name
      , 'N' as is_terminal
   from dual
   union all
   select
      'ESCALATED' as status_code
      , 'Escalated' as status_name
      , 'N' as is_terminal
   from dual
   union all
   select
      'CLOSED' as status_code
      , 'Closed' as status_name
      , 'Y' as is_terminal
   from dual
) s
   on (t.status_code = s.status_code)
when not matched then
   insert (status_code, status_name, is_terminal)
   values (s.status_code, s.status_name, s.is_terminal);

-- Allowed status changes: Open -> Assigned -> In review -> (Closed | Escalated -> Closed)
merge into case_status_transition t
using (
   select
      'OPEN' as from_status
      , 'ASSIGNED' as to_status
   from dual
   union all
   select
      'ASSIGNED' as from_status
      , 'IN_REVIEW' as to_status
   from dual
   union all
   select
      'IN_REVIEW' as from_status
      , 'CLOSED' as to_status
   from dual
   union all
   select
      'IN_REVIEW' as from_status
      , 'ESCALATED' as to_status
   from dual
   union all
   select
      'ESCALATED' as from_status
      , 'CLOSED' as to_status
   from dual
   union all
   select
      'CLOSED' as from_status
      , 'IN_REVIEW' as to_status
   from dual
) s
   on (t.from_status = s.from_status and t.to_status = s.to_status)
when not matched then
   insert (from_status, to_status) values (s.from_status, s.to_status);

merge into app_user t
using (
   select
      'analyst_demo' as username
      , 'Demo Analyst' as full_name
   from dual
   union all
   select
      'manager_demo' as username
      , 'Demo Manager' as full_name
   from dual
) s
   on (t.username = s.username)
when not matched then
   insert (username, full_name) values (s.username, s.full_name);

merge into user_role t
using (
   select
      u.user_id
      , r.role_id
   from app_user u
   inner join app_role r
      on
         (u.username = 'analyst_demo' and r.role_code = 'ANALYST')
         or (u.username = 'manager_demo' and r.role_code = 'MANAGER')
) s
   on (t.user_id = s.user_id and t.role_id = s.role_id)
when not matched then
   insert (user_id, role_id) values (s.user_id, s.role_id);

merge into review_rule t
using (
   select
      'DLQ60_ENTRY' as rule_code
      , 'First entry into 60+ day delinquency this month' as rule_name
   from dual
) s
   on (t.rule_code = s.rule_code)
when not matched then
   insert (rule_code, rule_name) values (s.rule_code, s.rule_name);

merge into review_rule_version t
using (
   select
      rule_id
      , 1 as version_no
      , 2 as min_delinquency_status
      , date '1999-01-01' as effective_from
      , 'Prior month below 02 or absent; this month 02+ or RA: candidate'
      || ' (User Guide p.10 status codes; RA follows metric definition 1)'
         as rule_desc
   from review_rule
   where rule_code = 'DLQ60_ENTRY'
) s
   on (t.rule_id = s.rule_id and t.version_no = s.version_no)
when not matched then
   insert (
      rule_id, version_no, min_delinquency_status, effective_from, rule_desc
   )
   values (
      s.rule_id
      , s.version_no
      , s.min_delinquency_status
      , s.effective_from
      , s.rule_desc
   );

commit;
