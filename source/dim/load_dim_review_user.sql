-- Name: load_dim_review_user.sql
-- Purpose: build SCD2 rows one OLTP event at a time in event-time order; progress is recorded only in the warehouse's per-event watermark table.
--          Versions from before events existed keep their observed time and do not pretend to be business change times.
-- Usage: cdc_review calls load_dim_review_user(systimestamp).
-- Requires: dim_review_user_identity, dim_review_user, etl_user_event_watermark, loan_oltp.user_change_event.
-- SQLFluff does not understand field references on the PL/SQL cursor record e.
-- noqa: disable=RF01,RF03,AL09

create or replace procedure load_dim_review_user(
   in_observed_at in timestamp default systimestamp
) is
   l_key dim_review_user.user_version_key%type;
   l_username dim_review_user.username%type;
   l_full_name dim_review_user.full_name%type;
   l_active dim_review_user.is_active%type;
   l_roles dim_review_user.role_list%type;
   l_manager dim_review_user.is_manager%type;
   l_from dim_review_user.valid_from%type;
begin
   if in_observed_at is null then
      raise_application_error(-20046, 'User dimension observation time must not be empty');
   end if;

   for e in (
      select
         event_id
         , user_id
         , event_at
         , username
         , full_name
         , is_active
         , role_list
         , is_manager
      from loan_oltp.user_change_event e
      where
         e.event_at <= in_observed_at
         and not exists (
            select 1
            from etl_user_event_watermark w
            where w.event_id = e.event_id
         )
      order by e.event_at, e.event_id
   ) loop
      merge into dim_review_user_identity t
      using (select e.user_id as user_id from dual) s
         on (t.user_id = s.user_id)
      when not matched then
         insert (user_id) values (s.user_id);

      begin
         select
            user_version_key
            , username
            , full_name
            , is_active
            , role_list
            , is_manager
            , valid_from
         into l_key, l_username, l_full_name, l_active
         , l_roles, l_manager, l_from
         from dim_review_user
         where user_id = e.user_id and is_current = 'Y'
         for update;

         if e.event_at <= l_from then
            raise_application_error(
               -20047, 'User event is earlier than the synced version; check transaction commit order: ' || e.user_id
            );
         end if;
         if l_username != e.username
         or l_full_name != e.full_name
         or l_active != e.is_active
         or coalesce(l_roles, chr(0)) != coalesce(e.role_list, chr(0))
         or l_manager != e.is_manager
         then
            update dim_review_user
            set valid_to = e.event_at, is_current = 'N'
            where user_version_key = l_key;
            insert into dim_review_user (
               user_id, username, full_name, is_active, role_list, is_manager
               , valid_from, valid_to, is_current
            ) values (
               e.user_id, e.username, e.full_name, e.is_active
               , e.role_list, e.is_manager, e.event_at, null, 'Y'
            );
         end if;
         exception
            when no_data_found then
               insert into dim_review_user (
                  user_id, username, full_name, is_active, role_list, is_manager
                  , valid_from, valid_to, is_current
               ) values (
                  e.user_id, e.username, e.full_name, e.is_active
                  , e.role_list, e.is_manager, e.event_at, null, 'Y'
               );
      end;
      insert into etl_user_event_watermark (event_id, applied_at)
      values (e.event_id, in_observed_at);
   end loop;
end load_dim_review_user;
/
-- noqa: enable=RF01,RF03,AL09
