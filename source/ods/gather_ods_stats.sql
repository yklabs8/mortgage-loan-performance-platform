-- Name: gather_ods_stats.sql
-- Purpose: gather optimizer statistics for the four ODS tables, their partitions, and global primary-key indexes
--          after a large rebuild.
-- Usage: scripts/run_sql.sh source/ods/gather_ods_stats.sql
-- Requires: the four partitioned ODS tables loaded
-- Called by: run manually after a full ODS rebuild or a large batch of file loads

declare
   l_table varchar2(30);
begin
   for i in 1..4 loop
      l_table := case i
         when 1 then 'ODS_ORIG'
         when 2 then 'ODS_PERF'
         when 3 then 'ODS_ORIG_PRE202607'
         else 'ODS_PERF_PRE202607'
      end;
      dbms_stats.gather_table_stats(
         ownname => user
         , tabname => l_table
         , estimate_percent => dbms_stats.auto_sample_size
         , cascade => true
         , granularity => 'ALL'
      );
      dbms_output.put_line(l_table || ' statistics updated');
   end loop;
end;
/
