-- Name: ods_file_hash.sql
-- Purpose: create function ods_file_hash, which fingerprints one release + one source file in an ODS table
--          and returns "row count/sum of row hashes".
--          Used to check that data loaded into a staging table, and then exchanged into the real partition,
--          matches the source file.
--          Row hash: each column written as "length:value" (null written as ~), concatenated, first 60 bits of SHA-256
-- Requires: ODS tables created
-- Called by: python/load_ods.py, source/ods/ods_exchange_file.sql

create or replace function ods_file_hash(
   in_table in varchar2
   , in_release_id in varchar2
   , in_file_name in varchar2
) return varchar2 is
   l_row_expr varchar2(32767);
   l_rows number;
   l_hash_sum number;
begin
   if lower(in_table) not like 'ods\_%' escape '\' then
      raise_application_error(-20031, 'Not an ODS table: ' || in_table);
   end if;

   -- each column (except release_id, source_file) written as "length:value", concatenated in column order; all ODS columns are text
   for r_col in (
      select column_name
      from user_tab_columns
      where
         table_name = upper(in_table)
         and column_name not in ('RELEASE_ID', 'SOURCE_FILE')
      order by column_id
   ) loop
      l_row_expr := l_row_expr
      || case when l_row_expr is not null then ' || ' end
      || 'case when ' || dbms_assert.simple_sql_name(r_col.column_name)
      || ' is null then ''~'' else length('
      || dbms_assert.simple_sql_name(r_col.column_name) || ') || '':'' || '
      || dbms_assert.simple_sql_name(r_col.column_name) || ' end';
   end loop;

   execute immediate
      'select count(*), coalesce(sum(to_number(substr(rawtohex(standard_hash('
      || l_row_expr || ', ''SHA256'')), 1, 15), ''XXXXXXXXXXXXXXX'')), 0) from '
      || dbms_assert.simple_sql_name(in_table)
      || ' where release_id = :1 and source_file = :2'
      into l_rows, l_hash_sum
      using in_release_id, in_file_name;
   return l_rows || '/' || l_hash_sum;
end ods_file_hash;
/
