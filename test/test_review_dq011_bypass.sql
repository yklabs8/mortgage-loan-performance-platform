-- Name: test_review_dq011_bypass.sql
-- Purpose: a restricted account writes an analyst's decision directly, and the DQ011 point-in-time role condition must find it; everything rolls back.
-- Usage: ORACLE_USER=loan_test scripts/run_sql.sh test/test_review_dq011_bypass.sql
-- Requires: no role trigger; loan_test has the test DML and read-only access to the user dimension.
-- Called by: run manually

alter session set current_schema = loan_oltp;

declare
   l_created pls_integer;
   l_candidate number;
   l_case number;
   l_analyst number;
   l_decision number;
   l_bad number;
begin
   if user != 'LOAN_TEST' then
      raise_application_error(-20046, 'This counterexample must run as loan_test');
   end if;
   review_api.generate_candidates(
      'R47', date '2020-06-01', 'DLQ60_ENTRY', l_created
   );
   select min(c.candidate_id) into l_candidate
   from review_candidate c
   where exists (
      select 1 from loan_dw.dim_loan d
      where d.release_id = 'R47' and d.loan_identifier = c.loan_identifier
   ) and not exists (
      select 1 from risk_review_case rc
      where rc.candidate_id = c.candidate_id
   );
   select user_id into l_analyst from app_user
   where username = 'analyst_demo';
   -- Rule out the false positive of "every row reported bad because the user dimension is entirely missing".
   select count(*) into l_bad from loan_dw.dim_review_user
   where
      user_id = l_analyst and is_manager = 'N'
      and systimestamp >= valid_from
      and (systimestamp < valid_to or valid_to is null);
   if l_bad != 1 then
      raise_application_error(-20046, 'The analyst''s current user dimension row must exist and not be a manager');
   end if;
   insert into risk_review_case (
      case_number, candidate_id, opened_by_user_id, updated_by_user_id
   ) values (
      'RRC-' || lpad(risk_review_case_seq.nextval, 6, '0')
      , l_candidate, l_analyst, l_analyst
   ) returning case_id into l_case;
   -- Even with MANAGER written falsely, DQ011 checks against the user dimension at decision time and ignores the role claimed in the row.
   insert into review_decision (
      case_id, decision_type, decided_by_user_id, decided_as_role, decision_note
   ) values (
      l_case, 'CLOSE', l_analyst, 'MANAGER', 'analyst decision bypassing Java'
   ) returning decision_id into l_decision;

   select count(*) into l_bad
   from loan_oltp.review_decision d
   left join loan_dw.dim_review_user u
      on
         d.decided_by_user_id = u.user_id
         and d.decided_at >= u.valid_from
         and (d.decided_at < u.valid_to or u.valid_to is null)
   where
      coalesce(u.is_manager, 'N') != 'Y'
      and d.decision_id = l_decision;  -- noqa: RF02
   if l_bad != 1 then
      raise_application_error(-20046, 'DQ011 did not find the analyst decision');
   end if;
   dbms_output.put_line('DQ011 found 1 analyst decision that bypassed Java; rolled back');
   rollback;
   exception
      when others then
         rollback;
         raise;
end;
/
