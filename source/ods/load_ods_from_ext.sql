-- load_ods_from_ext.sql
-- Validate identifiers, filenames, column counts and nonempty input before loading. Fill and fingerprint the exchange stage first; preserve the current partition on failure before exchange. A nonempty stage requires investigation. Nonpartitioned fixtures use transactional replacement.
create or replace procedure load_ods_from_ext(
   in_release_id in varchar2
   , in_table in varchar2
   , in_file_name in varchar2
) is
   l_table varchar2(30);
   l_ext_table varchar2(30);
   l_columns varchar2(4000);
   l_column_count pls_integer;
   l_file_rows pls_integer;
   l_bad_rows pls_integer;
   l_deleted pls_integer;
   l_inserted pls_integer;
   l_stage varchar2(30);
   l_partitioned varchar2(3);
   l_stage_rows pls_integer;
   l_stage_hash varchar2(100);
begin
   l_table := lower(in_table);
   if l_table not in ('ods_orig', 'ods_perf') then
      raise_application_error(-20021, 'Only ods_orig and ods_perf are supported: ' || in_table);
   end if;
   if not regexp_like(in_file_name, '^[A-Za-z0-9_.]+$') then
      raise_application_error(-20022, 'Invalid filename: ' || in_file_name);
   end if;
   if not regexp_like(in_release_id, '^[A-Za-z0-9_]+$') then
      raise_application_error(-20023, 'Invalid release_id: ' || in_release_id);
   end if;
   l_ext_table := 'ext_' || l_table;
   l_stage := l_table || '_stage';
   select partitioned into l_partitioned
   from user_tables
   where table_name = upper(l_table);

   select
      listagg(lower(column_name), ', ') within group (
         order by column_id
      ) as column_list
      , count(*) as column_count
   into l_columns, l_column_count
   from user_tab_columns
   where
      table_name = upper(l_table)
      and column_name not in ('RELEASE_ID', 'SOURCE_FILE');

   execute immediate
      'alter table ext_ods_raw_line location ('
      || dbms_assert.enquote_literal(in_file_name) || ')';
   execute immediate
      'alter table ' || dbms_assert.simple_sql_name(l_ext_table)
      || ' location (' || dbms_assert.enquote_literal(in_file_name) || ')';

   select
      count(*) as file_rows
      , count(
         case
            when
               coalesce(length(raw_line), 0)
               - coalesce(length(replace(raw_line, '|')), 0)
               != l_column_count - 1
               then 1
         end
      ) as bad_rows
   into l_file_rows, l_bad_rows
   from ext_ods_raw_line;
   if l_file_rows = 0 then
      raise_application_error(-20024, in_file_name || ' is empty');
   end if;
   if l_bad_rows > 0 then
      raise_application_error(
         -20025
         , in_file_name || ' has ' || l_bad_rows || ' rows with column count other than ' || l_column_count
         || '; nothing loaded'
      );
   end if;

   if l_partitioned = 'YES' then
      execute immediate
         'select count(*) from ' || dbms_assert.simple_sql_name(l_stage)
         into l_stage_rows;
      if l_stage_rows != 0 then
         raise_application_error(-20027, 'Stage is not empty; inspect the previous exchange before retrying');
      end if;
      execute immediate
         'insert into ' || dbms_assert.simple_sql_name(l_stage)
         || ' (' || l_columns || ', release_id, source_file) select '
         || l_columns
         || ', :1, :2 from ' || dbms_assert.simple_sql_name(l_ext_table)
         using in_release_id, in_file_name;
      l_deleted := 0;
   else
      execute immediate
         'delete from ' || dbms_assert.simple_sql_name(l_table)
         || ' where release_id = :1 and source_file = :2'
         using in_release_id, in_file_name;
      l_deleted := sql%rowcount;
      execute immediate
         'insert into ' || dbms_assert.simple_sql_name(l_table)
         || ' (' || l_columns || ', release_id, source_file) select '
         || l_columns
         || ', :1, :2 from ' || dbms_assert.simple_sql_name(l_ext_table)
         using in_release_id, in_file_name;
   end if;
   l_inserted := sql%rowcount;

   if l_inserted != l_file_rows then
      raise_application_error(
         -20026
         , 'File ' || l_file_rows || ' rows, inserted ' || l_inserted || ' rows; mismatch, rolled back'
      );
   end if;
   if l_partitioned = 'YES' then
      l_stage_hash := ods_file_hash(l_stage, in_release_id, in_file_name);
      commit;
      ods_exchange_file(l_table, in_release_id, in_file_name, l_stage_hash);
      dbms_output.put_line(
         l_table || ' ' || in_release_id || ' ' || in_file_name
         || ': external table loaded ' || l_inserted || ' rows; partition exchange complete'
      );
   else
      insert into ods_load_event (release_id, source_table, source_file)
      values (in_release_id, l_table, in_file_name);
      commit;
      dbms_output.put_line(
         l_table || ' ' || in_release_id || ' ' || in_file_name
         || ': removed old rows ' || l_deleted || ' rows; file '
         || l_file_rows || ' rows, loaded ' || l_inserted || ' rows; counts match'
      );
   end if;
   exception
      when others then
         rollback;
         raise;
end load_ods_from_ext;
/
