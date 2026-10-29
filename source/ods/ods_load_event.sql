-- ods_load_event.sql
-- Ods load event. See docs/metric_definitions.md for analytical definitions.
create table ods_load_event (
   event_id number generated always as identity
   , release_id varchar2(10) not null
   , source_table varchar2(30) not null
   , source_file varchar2(100) not null
   , loaded_at timestamp(6) default systimestamp not null
   , constraint ods_load_event_pk primary key (event_id)
);

create index ods_load_event_release_idx
on ods_load_event (release_id, loaded_at);

-- noqa: disable=LT05
comment on table ods_load_event is 'Successful source-file load completion times; checks must be newer than the last load for their release';
comment on column ods_load_event.event_id is 'Load event ID';
comment on column ods_load_event.release_id is 'Loaded release';
comment on column ods_load_event.source_table is 'Loaded ODS target table';
comment on column ods_load_event.source_file is 'Replaced source filename';
comment on column ods_load_event.loaded_at is 'Database timestamp when this source-file load completed';
-- noqa: enable=LT05
