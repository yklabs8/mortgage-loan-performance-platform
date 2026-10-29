-- load_dim_servicer.sql
-- MERGE keeps existing keys and updates standardized names (SCD Type 1). Missing names use key 0. Earlier-layout OTHER SERVICERS maps to OTHER (Disclosure Changes v1.2 p.4). Uppercase names, replace ampersands with AND, remove periods, normalize punctuation and spaces.
create or replace procedure load_dim_servicer(
   in_release_id in varchar2
) is
   co_unknown_key constant number := 0;  
   co_unknown_name constant varchar2(20) := '(NOT PROVIDED)';
begin
   merge into dim_servicer t
   using (
      select
         co_unknown_key as servicer_key
         , co_unknown_name as servicer_name
      from dual
   ) s
      on (t.servicer_key = s.servicer_key)
   when matched then
      update set
         servicer_name = s.servicer_name
         , servicer_std_name = s.servicer_name
         , name_status = 'NOT_PROVIDED'
   when not matched then
      insert (servicer_key, servicer_name, servicer_std_name, name_status)
      values (s.servicer_key, s.servicer_name, s.servicer_name, 'NOT_PROVIDED');

   merge into dim_servicer t
   using (
      with

      release_names as (
         select servicer_name
         from ods_perf
         where release_id = in_release_id
         union
         select
            case
               when upper(servicer_name) = 'OTHER SERVICERS' then 'OTHER'
               else servicer_name
            end as servicer_name
         from ods_orig_pre202607
         where release_id = in_release_id
      )

      , std as (
         select
            servicer_name
            , trim(
               regexp_replace(
                  regexp_replace(
                     replace(
                        upper(replace(servicer_name, chr(38), ' AND '))
                        , '.'
                     )
                     , '[^A-Z0-9 ]'
                     , ' '
                  )
                  , ' {2,}'
                  , ' '
               )
            ) as servicer_std_name
         from release_names
         where servicer_name is not null
      )

      select
         servicer_name
         , servicer_std_name
         , case
            when servicer_std_name = 'OTHER' then 'OTHER'
            else 'NAMED'
         end as name_status
      from std
   ) s
      on (t.servicer_name = s.servicer_name)
   when matched then
      update set
         servicer_std_name = s.servicer_std_name
         , name_status = s.name_status
   when not matched then
      insert (servicer_name, servicer_std_name, name_status)
      values (s.servicer_name, s.servicer_std_name, s.name_status);
end load_dim_servicer;
/
