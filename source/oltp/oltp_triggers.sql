-- Name: oltp_triggers.sql
-- Purpose: create the triggers of the risk review system, so the database guards the business rules (constraints, triggers, and stored
--          procedures enforce data integrity and workflow rules):
--          1. Tables that change: updated_at is maintained automatically on update (for timestamp-based CDC)
--          2. Case status may change only as case_status_transition allows; a new case must be OPEN (DQ010)
--          3. Every case status change automatically writes a row to case_status_history
--          Role rules are enforced by the Java service layer; a wrong decision that bypasses Java is found afterwards by DQ011
-- Requires: oltp_tables.sql has run
-- Called by: scripts/run_sql.sh source/oltp/oltp_triggers.sql
-- Note: trigger names follow Trivadis: table + action + _trg; error numbers start at -20010

-- ========== 1. Maintain updated_at automatically ==========

create or replace trigger app_user_updated_at_trg
before update on app_user
for each row
begin
   :new.updated_at := systimestamp;
end;
/

-- A user attribute event can read the other (role) table directly inside the row trigger.
create or replace trigger app_user_change_event_trg
after insert or update of username, full_name, is_active on app_user
for each row
declare
   l_roles varchar2(100);
   l_manager varchar2(1);
begin
   select
      listagg(r.role_code, ',') within group (order by r.role_code) as role_list
      , coalesce(max(case when r.role_code = 'MANAGER' then 'Y' end), 'N')
         as is_manager
   into l_roles, l_manager
   from user_role ur
   inner join app_role r on ur.role_id = r.role_id
   where ur.user_id = :new.user_id;
   insert into user_change_event (
      user_id, username, full_name, is_active, role_list, is_manager
   ) values (
      :new.user_id, :new.username, :new.full_name, :new.is_active
      , l_roles, l_manager
   );
end;
/

-- The role table cannot read itself inside a row trigger; the full role snapshot is taken after the statement.
-- SQLFluff does not parse the declaration section of a compound trigger; Oracle compilation verifies it.
-- noqa: disable=all
create or replace trigger user_role_change_event_trg
for insert or delete or update on user_role
compound trigger
   type t_user_ids is table of user_role.user_id%type index by pls_integer;
   l_user_ids t_user_ids;
   l_count pls_integer := 0;

   after each row is
   begin
      l_count := l_count + 1;
      if deleting then
         l_user_ids(l_count) := :old.user_id;
      else
         l_user_ids(l_count) := :new.user_id;
      end if;
      if updating and :old.user_id != :new.user_id then
         l_count := l_count + 1;
         l_user_ids(l_count) := :old.user_id;
      end if;
   end after each row;

   after statement is
   begin
      for i in 1 .. l_count loop
         insert into user_change_event (
            user_id, username, full_name, is_active, role_list, is_manager
         )
         select
            a.user_id, a.username, a.full_name, a.is_active
            , listagg(r.role_code, ',') within group (order by r.role_code)
            , coalesce(max(case when r.role_code = 'MANAGER' then 'Y' end), 'N')
         from app_user a
         left join user_role ur on ur.user_id = a.user_id
         left join app_role r on r.role_id = ur.role_id
         where a.user_id = l_user_ids(i)
         group by a.user_id, a.username, a.full_name, a.is_active;
      end loop;
   end after statement;
end user_role_change_event_trg;
/
-- noqa: enable=all

create or replace trigger review_rule_updated_at_trg
before update on review_rule
for each row
begin
   :new.updated_at := systimestamp;
end;
/

create or replace trigger case_annotation_updated_at_trg
before update on case_annotation
for each row
begin
   :new.updated_at := systimestamp;
end;
/

-- ========== 2. Case status changes only along allowed paths ==========

create or replace trigger risk_review_case_status_trg
before insert or update on risk_review_case
for each row
declare
   l_allowed pls_integer;
   l_terminal case_status.is_terminal%type;
begin
   :new.updated_at := systimestamp;
   if inserting then
      if :new.current_status != 'OPEN' then
         raise_application_error(-20010, 'A new case must have status OPEN');
      end if;
   elsif :old.current_status != :new.current_status then
      select count(*)
      into l_allowed
      from case_status_transition
      where
         from_status = :old.current_status
         and to_status = :new.current_status;
      if l_allowed = 0 then
         raise_application_error(
            -20010
            , 'Status change not allowed: ' || :old.current_status
            || ' → ' || :new.current_status
         );
      end if;
      -- Record the close time on entering a terminal status
      select is_terminal
      into l_terminal
      from case_status
      where status_code = :new.current_status;
      if l_terminal = 'Y' then
         :new.closed_at := systimestamp;
      elsif :old.current_status = 'CLOSED' then
         -- Reopening returns to review; the old close decision stays in the review_decision audit table.
         :new.closed_at := null;
      end if;
   end if;
end;
/

-- ========== 3. Write history on every status change ==========

create or replace trigger risk_review_case_history_trg
after insert or update of current_status on risk_review_case
for each row
begin
   if inserting then
      -- Opening a case: no previous status
      insert into case_status_history (
         case_id, from_status, to_status, changed_by_user_id
      ) values (
         :new.case_id, null, :new.current_status, :new.updated_by_user_id
      );
   elsif :old.current_status != :new.current_status then
      insert into case_status_history (
         case_id, from_status, to_status, changed_by_user_id
      ) values (
         :new.case_id
         , :old.current_status
         , :new.current_status
         , :new.updated_by_user_id
      );
   end if;
end;
/
