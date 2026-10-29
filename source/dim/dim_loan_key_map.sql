-- dim_loan_key_map.sql
-- Dim loan key map. See docs/metric_definitions.md for analytical definitions.
create table dim_loan_key_map (
   loan_durable_key number generated always as identity
   , data_source varchar2(3) not null
   , loan_identifier varchar2(12) not null
   , first_release_id varchar2(10) not null
   , constraint dim_loan_key_map_pk primary key (loan_durable_key)
   , constraint dim_loan_key_map_loan_uk unique (data_source, loan_identifier)
   , constraint dim_loan_key_map_data_source_ck check (
      data_source in ('FRE')
   )
);

-- noqa: disable=LT05
comment on table dim_loan_key_map is 'DIM: one durable key per agency and loan ID. Insert only: the first load assigns the key and later releases reuse it. The surrogate key distinguishes release versions; the durable key links the same loan across versions.';
comment on column dim_loan_key_map.loan_durable_key is 'Durable key, stable across releases for the same loan';
comment on column dim_loan_key_map.data_source is 'Source agency: FRE = Freddie Mac; agency and loan ID form the business identity';
comment on column dim_loan_key_map.loan_identifier is 'Agency-specific loan identifier';
comment on column dim_loan_key_map.first_release_id is 'Release that first loaded this loan, by processing order rather than release date; informational only';
-- noqa: enable=LT05
