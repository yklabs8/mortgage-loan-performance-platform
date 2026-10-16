-- Load one release through the first warehouse path, using the existing partition exchange sequence.
create or replace procedure load_dw_release(
   in_release_id in varchar2
) is
   l_partition varchar2(128);
   l_exists pls_integer;
begin
   if not regexp_like(in_release_id, '^[A-Za-z0-9_]+$') then
      raise_application_error(-20012, 'Invalid release_id: ' || in_release_id);
   end if;
   l_partition := dbms_assert.simple_sql_name('P_' || upper(in_release_id));
   execute immediate 'truncate table dwd_loan_monthly_perf_stage';
   select count(*)
   into l_exists
   from user_tab_partitions
   where
      table_name = 'DWD_LOAN_MONTHLY_PERF'
      and partition_name = l_partition;
   if l_exists = 0 then
      execute immediate
         'alter table dwd_loan_monthly_perf split partition p_default'
         || ' values (' || dbms_assert.enquote_literal(in_release_id)
         || ') into (partition ' || l_partition || ', partition p_default)';
   end if;

   begin
      load_dim_loan(in_release_id);
      load_dwd_loan_monthly_perf(in_release_id);
      commit;
      exception
         when others then
            rollback;
            raise;
   end;

   execute immediate
      'alter table dwd_loan_monthly_perf exchange partition ' || l_partition
      || ' with table dwd_loan_monthly_perf_stage'
      || ' including indexes without validation';

   begin
      load_dws_perf_loan_td(in_release_id);
      load_ads_vintage_dlq60_curve(in_release_id);
      commit;
      exception
         when others then
            rollback;
            raise_application_error(
               -20011
               , in_release_id || ' summary failed; rerun load.'
               , true
            );
   end;
   execute immediate 'truncate table dwd_loan_monthly_perf_stage';

   begin
      gather_dw_stats;
      exception
         when others then
            raise_application_error(
               -20010
               , in_release_id || ' data committed; statistics failed.'
               , true
            );
   end;
end load_dw_release;
/
