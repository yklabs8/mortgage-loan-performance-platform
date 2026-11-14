-- Name: dim_review_user.sql
-- Purpose: SCD2 review users; the stable user_id lives in an identity table referenced by fact foreign keys,
--          and dim_review_user keeps the old row and appends a new one whenever role, name, or active status changes.
-- Requires: none; on a fresh install run before the review fact tables.
-- Called by: scripts/run_sql.sh source/dim/dim_review_user.sql (run once).

create table dim_review_user_identity (
   user_id number not null
   , constraint dim_review_user_identity_pk primary key (user_id)
);

create table dim_review_user (
   user_version_key number generated always as identity
   , user_id number not null
   , username varchar2(30) not null
   , full_name varchar2(100) not null
   , is_active varchar2(1) not null
   , role_list varchar2(100)
   , is_manager varchar2(1) not null
   , valid_from timestamp(6) not null
   , valid_to timestamp(6)
   , is_current varchar2(1) not null
   , constraint dim_review_user_pk primary key (user_version_key)
   , constraint dim_review_user_user_from_uk unique (user_id, valid_from)
   , constraint dru_identity_fk foreign key (user_id)
   references dim_review_user_identity (user_id)
   , constraint dim_review_user_manager_ck check (is_manager in ('Y', 'N'))
   , constraint dim_review_user_current_ck check (is_current in ('Y', 'N'))
   , constraint dim_review_user_dates_ck check (
      (is_current = 'Y' and valid_to is null)
      or (is_current = 'N' and valid_to > valid_from)
   )
);

begin
   execute immediate
      'create unique index dim_review_user_one_current_ix'
      || ' on dim_review_user (case when is_current = ''Y'' then user_id end)';
end;
/

-- noqa: disable=LT05
comment on table dim_review_user_identity is 'Stable natural key of review users; case fact tables reference user_id here so the user dimension can keep several historical versions';
comment on table dim_review_user is 'Review user SCD2: a new row each time a user''s role, name, or active status changes; valid_to is exclusive';
comment on column dim_review_user.user_version_key is 'SCD2 version surrogate key';
comment on column dim_review_user.user_id is 'OLTP user ID; one user can have several versions';
comment on column dim_review_user.username is 'Login name of this version';
comment on column dim_review_user.full_name is 'Full name of this version';
comment on column dim_review_user.is_active is 'Whether this version is active';
comment on column dim_review_user.role_list is 'Roles of this version, sorted by code and comma-separated';
comment on column dim_review_user.is_manager is 'Whether this version has the manager role';
comment on column dim_review_user.valid_from is 'After events were introduced, the OLTP attribute or role change time; versions from before keep their observed time, and the earliest 1900 value marks an unknown start; inclusive';
comment on column dim_review_user.valid_to is 'Time of the next event; versions from before events keep the next CDC observation time; exclusive, empty for the current version';
comment on column dim_review_user.is_current is 'Y = current version, N = historical version';
-- noqa: enable=LT05
