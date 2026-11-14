-- The warehouse's own sync watermark for user events. One row per applied event_id; the maximum is the highest synced ID.
-- Each event is recorded individually so that an OLTP transaction with a smaller ID that commits later is not missed.
create table etl_user_event_watermark (
   event_id number not null
   , applied_at timestamp(6) default systimestamp not null
   , constraint etl_user_event_watermark_pk primary key (event_id)
);

comment on table etl_user_event_watermark is 'User events already synced into the warehouse; recorded one ID at a time so late commits are not missed';
comment on column etl_user_event_watermark.event_id is 'Synced OLTP event ID';
comment on column etl_user_event_watermark.applied_at is 'When the event reached the warehouse dimension';
