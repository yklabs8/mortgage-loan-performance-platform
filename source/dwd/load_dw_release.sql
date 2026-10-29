-- load_dw_release.sql
-- Prepare the exchange stage and release partition (DDL commits). Load dimensions and stage in one transaction. Exchange the checked partition, then recompute summaries and analyses in another transaction. A post-exchange failure requires a rerun; statistics failure is reported separately. A base release enables targeted recomputation.
create or replace procedure load_dw_release(
   in_release_id in varchar2
   , in_base_release_id in varchar2 default null
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
      load_dim_servicer(in_release_id);
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
      if in_base_release_id is null then
         load_dws_perf_loan_td(in_release_id);
         load_dws_mod_loan_td(in_release_id);
         load_ads_vintage_dlq60_curve(in_release_id);
         load_ads_dlq_transition_monthly(in_release_id);
         load_ads_modification_outcome(in_release_id);
         load_ads_dlq_transition_segment(in_release_id);
         load_ads_final_outcome_segment(in_release_id);
         load_ads_cure_redefault_segment(in_release_id);
         load_ads_vintage_dlq60_segment(in_release_id);
         load_ads_modification_segment(in_release_id);
      else
         recompute_downstream_targeted(in_base_release_id, in_release_id);
      end if;
      commit;
      exception
         when others then
            rollback;
            raise_application_error(
               -20011
               , in_release_id || ' detail has been exchanged, but summary/analysis recomputation failed; '
               || 'investigate and rerun load_dw_release'
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
               , in_release_id || ' data was loaded and committed; optimizer statistics collection failed; '
               || 'recovery: run exec gather_dw_stats separately'
               , true  
            );
   end;
end load_dw_release;
/
