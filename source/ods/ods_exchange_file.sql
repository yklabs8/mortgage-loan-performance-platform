-- Name: ods_exchange_file.sql
-- Purpose: exchange a checked staging table with the partition of a given release + file, keeping the
--          original cross-file unique primary key.
-- Usage: scripts/run_sql.sh source/ods/ods_exchange_file.sql
-- Requires: the four partitioned ODS tables, their staging tables, function ods_file_hash
-- Called by: python/load_ods.py
-- Note: split and exchange are DDL and commit automatically. On failure the staging table is not cleaned up;
--       find out the state first, then recover.

create or replace procedure ods_exchange_file(
   in_table in varchar2
   , in_release_id in varchar2
   , in_file_name in varchar2
   , in_expected_hash in varchar2
) is
   l_table varchar2(30);
   l_stage varchar2(30);
   l_stage_pk varchar2(30);
   l_partition varchar2(30);
   l_total number;
   l_scoped number;
   l_partition_exists pls_integer;
   l_index_status varchar2(10);
   l_stage_hash varchar2(100);
   l_final_hash varchar2(100);
begin
   l_table := lower(in_table);
   if l_table not in (
      'ods_orig', 'ods_perf', 'ods_orig_pre202607'
      , 'ods_perf_pre202607', 'ods_zz_exchange'
   ) then
      raise_application_error(-20062, 'Unsupported ODS table: ' || in_table);
   end if;
   if not regexp_like(in_release_id, '^[A-Za-z0-9_]+$')
   or not regexp_like(in_file_name, '^[A-Za-z0-9_.]+$') then
      raise_application_error(-20063, 'Invalid release or file name format');
   end if;
   l_stage := l_table || '_stage';
   l_stage_pk := l_stage || '_pk';
   select status into l_index_status
   from user_indexes
   where index_name = upper(l_stage_pk);
   if l_index_status != 'VALID' then
      -- the staging table's primary-key index is unusable
      raise_application_error(-20064, 'Stage index unusable: ' || l_stage_pk);
   end if;

   execute immediate
      'select count(*) from ' || dbms_assert.simple_sql_name(l_stage)
      into l_total;
   execute immediate
      'select count(*) from ' || dbms_assert.simple_sql_name(l_stage)
      || ' where release_id = :1 and source_file = :2'
      into l_scoped using in_release_id, in_file_name;
   if l_total = 0 or l_total != l_scoped then
      -- the staging table is empty, or also holds rows from another release or file
      raise_application_error(-20065, 'Stage empty or mixed; not exchanged');
   end if;
   l_stage_hash := ods_file_hash(l_stage, in_release_id, in_file_name);
   if l_stage_hash != in_expected_hash then
      -- the staging fingerprint differs from the one the loader recorded
      raise_application_error(-20066, 'Stage hash mismatch; not exchanged');
   end if;

   select 'P_' || substr(rawtohex(standard_hash(
      in_release_id || chr(0) || in_file_name, 'SHA256'
   )), 1, 24) into l_partition from dual;
   select count(*) into l_partition_exists
   from user_tab_partitions
   where table_name = upper(l_table) and partition_name = l_partition;
   if l_partition_exists = 0 then
      execute immediate
         'alter table ' || dbms_assert.simple_sql_name(l_table)
         || ' split partition p_default values (('
         || dbms_assert.enquote_literal(in_release_id) || ', '
         || dbms_assert.enquote_literal(in_file_name)
         || ')) into (partition ' || dbms_assert.simple_sql_name(l_partition)
         || ', partition p_default) update indexes';
   end if;

   execute immediate
      'alter table ' || dbms_assert.simple_sql_name(l_table)
      || ' exchange partition ' || dbms_assert.simple_sql_name(l_partition)
      || ' with table ' || dbms_assert.simple_sql_name(l_stage)
      || ' excluding indexes with validation update global indexes';

   l_final_hash := ods_file_hash(l_table, in_release_id, in_file_name);
   if l_final_hash != in_expected_hash then
      -- fingerprint mismatch after the exchange: the old partition data is now in the staging table, do not clear it
      raise_application_error(-20067, 'Hash mismatch after swap; keep stage');
   end if;
   execute immediate 'truncate table ' || dbms_assert.simple_sql_name(l_stage);
   execute immediate
      'alter index ' || dbms_assert.simple_sql_name(l_stage_pk) || ' rebuild';
   dbms_output.put_line(
      l_table || ' ' || in_release_id || ' ' || in_file_name
      || ': partition exchanged, fingerprint ' || l_final_hash
   );
end ods_exchange_file;
/
