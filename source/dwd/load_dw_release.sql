-- Name: load_dw_release.sql
-- Purpose: reload one release's DIM, DWD, DWS, and ADS as a whole (Oracle partition exchange loading), in four stages:
--          Stage 1, prepare: truncate the stage table; if the detail table has no partition for this release, split one out of the default partition.
--                   Both steps are DDL and commit implicitly, but no data has changed yet
--          Stage 2, load: merge dimensions (loan, servicer), write new detail rows to the stage table and reconcile; one transaction, committed only if all succeed;
--                   on error everything is rolled back, the detail table is untouched, and the original error is raised
--          Stage 3, exchange: swap the stage table with this release's partition. Only the data dictionary changes, no data moves, so it is instant:
--                   new rows become the live partition and old rows move to the stage table. No need to delete old detail rows
--          Stage 4, aggregate: recompute the DWS and ADS layers in one transaction; on failure -20011 is raised, the detail is already new, rerun this procedure.
--                   Without a base release everything is recomputed; with a base release (in_base_release_id) recomputation is targeted:
--                   only loans affected relative to the base are recomputed (recompute_downstream_targeted), with results identical to a full recompute (checked by result fingerprint)
--                   Finally truncate the stage table (it holds the old rows) and gather statistics (failure raises -20010, as above)
-- Requires: load_dim_loan, load_dim_servicer, load_dwd_loan_monthly_perf, load_dws_perf_loan_td,
--           load_dws_mod_loan_td, load_ads_vintage_dlq60_curve, load_ads_dlq_transition_monthly,
--           load_ads_modification_outcome, recompute_downstream_targeted, gather_dw_stats exist; dwd_loan_monthly_perf is partitioned by release,
--           dwd_loan_monthly_perf_stage exists
-- load_dw_release.sql

create or replace procedure load_dw_release(
   in_release_id in varchar2
   , in_base_release_id in varchar2 default null
) is
   l_partition varchar2(128);
   l_exists pls_integer;
begin
   -- Stage 1: prepare. Partition name P_ + release_id, for example P_R47; release_id may contain only letters, digits, and underscores
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

   -- Stage 2: load, committed only if everything succeeds
   begin
      load_dim_loan(in_release_id);
      -- Detail rows look up the servicer key, so the servicer dimension must be loaded before the detail
      load_dim_servicer(in_release_id);
      load_dwd_loan_monthly_perf(in_release_id);
      commit;
      exception
         when others then
            rollback;
            raise;
   end;

   -- Stage 3: exchange. Every stage row passed primary- and foreign-key checks on insert, so no validation is repeated (without validation)
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
      -- Calculation records are published in the same transaction as the DWS/ADS results; DWS is recorded first so ADS can link its real parent calculation.
      record_dw_calculation(
         'DWS_PERF_LOAN_TD', in_release_id, in_base_release_id
      );
      record_dw_calculation(
         'DWS_MOD_LOAN_TD', in_release_id, in_base_release_id
      );
      record_dw_calculation(
         'ADS_VINTAGE_DLQ60_CURVE', in_release_id, in_base_release_id
      );
      record_dw_calculation(
         'ADS_DLQ_TRANSITION_MONTHLY', in_release_id, in_base_release_id
      );
      record_dw_calculation(
         'ADS_MODIFICATION_OUTCOME', in_release_id, in_base_release_id
      );
      record_dw_calculation(
         'ADS_DLQ_TRANSITION_SEGMENT', in_release_id, in_base_release_id
      );
      record_dw_calculation(
         'ADS_FINAL_OUTCOME_SEGMENT', in_release_id, in_base_release_id
      );
      record_dw_calculation(
         'ADS_CURE_REDEFAULT_SEGMENT', in_release_id, in_base_release_id
         , null, null, 'CURE_V1'
      );
      record_dw_calculation(
         'ADS_VINTAGE_DLQ60_SEGMENT', in_release_id, in_base_release_id
      );
      record_dw_calculation(
         'ADS_MODIFICATION_SEGMENT', in_release_id, in_base_release_id
      );
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
