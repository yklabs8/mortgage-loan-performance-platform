-- Record the result digest, source batches, and real parent calculations inside the caller's publishing transaction; this procedure does not commit.
-- The result digest hashes each full row with SHA-256, sums each of the four 64-bit segments, and hashes the totals with SHA-256.
-- Nested cursors, dynamic SQL, and multi-row value lists in PL/SQL are beyond what the SQLFluff Oracle formatter supports.
-- noqa: disable=LT01,LT02,LT04,LT05,LT09,LT14,AL04,RF02,AM04
create or replace procedure record_dw_calculation(
   in_table in varchar2
   , in_release_id in varchar2 default null
   , in_base_release_id in varchar2 default null
   , in_git_commit in varchar2 default null
   , in_metric_sha256 in varchar2 default null
   , in_algorithm_version in varchar2 default 'V1'
   , in_delivery_id in raw default null
) is
   l_table varchar2(40) := upper(in_table);
   l_read_table varchar2(128);
   l_has_current number;
   l_row_expr varchar2(20000);
   l_text varchar2(300);
   l_sql varchar2(32767);
   l_count number;
   l_sum1 number;
   l_sum2 number;
   l_sum3 number;
   l_sum4 number;
   l_digest varchar2(64);
   l_calc_id number;
   l_batch_id number;
   l_base_batch_id number;
   l_run_id number;
   l_cutoff date;
   l_parent_table varchar2(40);
   l_snapshot_count number;
   l_snapshot_rows number;
   l_hist_table varchar2(50);
   l_started timestamp(6) with time zone := systimestamp at time zone 'UTC';

   procedure attach_batch(in_release in varchar2, in_role in varchar2) is
      l_id number;
      l_verified timestamp;
      l_ods_latest timestamp;
   begin
      select source_batch_id, verified_at into l_id, l_verified
      from etl_source_batch
      where source_batch_id = (
         select max(source_batch_id) from etl_source_batch
         where release_id = in_release
            and status in ('SUCCESS', 'LEGACY_VERIFIED')
      );
      select max(loaded_at) into l_ods_latest
      from ods_load_event where release_id = in_release;
      if l_ods_latest is not null and l_verified < l_ods_latest then
         raise_application_error(-20111, 'ODS has a newer unverified load: ' || in_release);
      end if;
      insert into dw_calculation_input (calc_id, source_batch_id, input_role)
      values (l_calc_id, l_id, in_role);
      if in_role = 'TARGET' then
         l_batch_id := l_id;
      else
         l_base_batch_id := l_id;
      end if;
   end attach_batch;

   procedure attach_parent(in_parent_table in varchar2, in_release in varchar2) is
      l_parent_calc_id number;
   begin
      select max(calc_id) into l_parent_calc_id
      from dw_calculation
      where output_table = in_parent_table
         and release_id = in_release and status = 'SUCCESS';
      if l_parent_calc_id is null then
         raise_application_error(-20112, 'Missing parent DWS calculation: ' || in_parent_table);
      end if;
      insert into dw_calculation_parent (calc_id, parent_calc_id)
      values (l_calc_id, l_parent_calc_id);
   end attach_parent;
begin
   if l_table not in (
      'DWS_PERF_LOAN_TD', 'DWS_MOD_LOAN_TD',
      'ADS_VINTAGE_DLQ60_CURVE', 'ADS_DLQ_TRANSITION_MONTHLY',
      'ADS_MODIFICATION_OUTCOME', 'ADS_DLQ_TRANSITION_SEGMENT',
      'ADS_FINAL_OUTCOME_SEGMENT', 'ADS_CURE_REDEFAULT_SEGMENT',
      'ADS_VINTAGE_DLQ60_SEGMENT',
      'ADS_MODIFICATION_SEGMENT', 'ADS_RELEASE_DIFF_SUMMARY',
      'ADS_RELEASE_DIFF_DETAIL', 'ADS_REVIEW_CASE_MONTHLY'
   ) then
      raise_application_error(-20110, 'Unregistered calculation table: ' || in_table);
   end if;
   if l_table = 'ADS_REVIEW_CASE_MONTHLY' then
      if in_release_id is not null or in_base_release_id is not null then
         raise_application_error(-20113, 'The monthly review report has no release');
      end if;
   elsif in_release_id is null then
      raise_application_error(-20114, 'A loan analysis must specify a release');
   end if;

   l_read_table := l_table;
   select count(*) into l_has_current from user_views
   where view_name = l_table || '_CURRENT';
   if l_has_current = 1 then
      l_read_table := l_table || '_CURRENT';
   end if;
   for c in (
      select column_name, data_type from user_tab_columns
      where table_name = l_table and column_name != 'DELIVERY_ID' order by column_name
   ) loop
      if c.data_type = 'DATE' then
         l_text := 'to_char(' || c.column_name || ', ''yyyymmddhh24miss'')';
      elsif c.data_type like 'TIMESTAMP%' then
         l_text := 'to_char(' || c.column_name || ', ''yyyymmddhh24missff6'')';
      elsif c.data_type = 'NUMBER' then
         l_text := 'to_char(' || c.column_name || ', ''tm9'')';
      else
         l_text := c.column_name;
      end if;
      l_row_expr := l_row_expr
      || case when l_row_expr is not null then ' || ' end
      || 'case when ' || l_text || ' is null then ''~'' else length('
      || l_text || ') || '':'' || ' || l_text || ' end';
   end loop;
   if l_row_expr is null then
      raise_application_error(-20115, 'Result table not found: ' || l_table);
   end if;
   l_sql := 'select count(*)';
   for i in 0 .. 3 loop
      l_sql := l_sql || ', coalesce(sum(to_number(substr(rawtohex('
      || 'standard_hash(' || l_row_expr || ', ''SHA256'')), '
      || (i * 16 + 1) || ', 16), ''XXXXXXXXXXXXXXXX'')), 0)';
   end loop;
   l_sql := l_sql || ' from ' || dbms_assert.simple_sql_name(l_read_table);
   if l_table in ('ADS_RELEASE_DIFF_SUMMARY', 'ADS_RELEASE_DIFF_DETAIL') then
      l_sql := l_sql || ' where old_release_id = :1 and new_release_id = :2';
      execute immediate l_sql into l_count, l_sum1, l_sum2, l_sum3, l_sum4
      using in_base_release_id, in_release_id;
   elsif l_table = 'ADS_REVIEW_CASE_MONTHLY' then
      execute immediate l_sql into l_count, l_sum1, l_sum2, l_sum3, l_sum4;
   else
      l_sql := l_sql || ' where release_id = :1';
      execute immediate l_sql into l_count, l_sum1, l_sum2, l_sum3, l_sum4
      using in_release_id;
   end if;
   select rawtohex(standard_hash(
      l_count || '|' || l_sum1 || '|' || l_sum2 || '|' || l_sum3 || '|' || l_sum4,
      'SHA256'
   )) into l_digest from dual;

   if in_release_id is not null then
      select max(last_reporting_period) into l_cutoff
      from dws_perf_loan_td where release_id = in_release_id;
   end if;
   insert into dw_calculation (
      output_table, release_id, base_release_id, target_scope, run_id,
      started_at, published_at, status, result_rows, result_digest,
      git_commit, metric_sha256, parameters_json, algorithm_version,
      input_cutoff, delivery_id
   ) values (
      l_table, in_release_id, in_base_release_id,
      case when in_release_id is null then 'REVIEW_ALL' else 'RELEASE_ALL' end,
      null, l_started, systimestamp at time zone 'UTC',
      'SUCCESS', l_count, l_digest,
      coalesce(in_git_commit, sys_context('USERENV', 'CLIENT_IDENTIFIER')),
      coalesce(in_metric_sha256, sys_context('USERENV', 'CLIENT_INFO')),
      case when l_table = 'ADS_REVIEW_CASE_MONTHLY' then '{"mode":"CDC"}'
         when in_base_release_id is null then '{"mode":"FULL"}'
         else '{"mode":"TARGETED"}' end,
      in_algorithm_version,
      case when l_cutoff is null then null
         else from_tz(cast(l_cutoff as timestamp), 'UTC') end, in_delivery_id
   ) returning calc_id into l_calc_id;

   if in_release_id is not null then
      attach_batch(in_release_id, 'TARGET');
      select run_id into l_run_id from etl_source_batch
      where source_batch_id = l_batch_id;
      update dw_calculation set run_id = l_run_id where calc_id = l_calc_id;
      if in_base_release_id is not null then
         attach_batch(in_base_release_id, 'BASE');
      end if;
   else
      for r in (
         select c.* from etl_cdc_run c
         where c.run_id = (
            select max(c2.run_id) from etl_cdc_run c2
            where c2.source_name = c.source_name
         )
      ) loop
         insert into dw_calculation_cdc (
            calc_id, cdc_run_id, source_name, from_ts, to_ts,
            extracted_rows, loaded_rows, rule_version, input_digest
         ) values (
            l_calc_id, r.run_id, r.source_name, r.from_ts, r.to_ts,
            r.extracted_rows, r.loaded_rows,
            'RULE_MAX_' || (select max(rule_version_id) from dim_review_rule),
            rawtohex(standard_hash(
               r.source_name || '|' || to_char(r.from_ts, 'yyyymmddhh24missff6')
               || '|' || to_char(r.to_ts, 'yyyymmddhh24missff6')
               || '|' || r.extracted_rows || '|' || coalesce(r.loaded_rows, -1),
               'SHA256'
            ))
         );
      end loop;
   end if;

   if l_table in ('ADS_VINTAGE_DLQ60_CURVE', 'ADS_FINAL_OUTCOME_SEGMENT',
      'ADS_VINTAGE_DLQ60_SEGMENT', 'ADS_CURE_REDEFAULT_SEGMENT') then
      l_parent_table := 'DWS_PERF_LOAN_TD';
   elsif l_table in ('ADS_MODIFICATION_OUTCOME', 'ADS_MODIFICATION_SEGMENT') then
      l_parent_table := 'DWS_MOD_LOAN_TD';
   end if;
   if l_parent_table is not null then
      attach_parent(l_parent_table, in_release_id);
      if in_base_release_id is not null then
         attach_parent(l_parent_table, in_base_release_id);
      end if;
   end if;
   if l_table in (
      'ADS_VINTAGE_DLQ60_CURVE', 'ADS_DLQ_TRANSITION_MONTHLY',
      'ADS_MODIFICATION_OUTCOME', 'ADS_RELEASE_DIFF_SUMMARY',
      'ADS_RELEASE_DIFF_DETAIL', 'ADS_REVIEW_CASE_MONTHLY'
   ) then
      -- One full snapshot per successful publication, including zero-row publications.
      -- Serialise the 20-copy capacity check across concurrent publishers.
      execute immediate 'lock table dw_ads_snapshot in exclusive mode';
      select count(*) into l_snapshot_count
      from dw_ads_snapshot s
      inner join dw_calculation c on s.calc_id = c.calc_id
      where c.output_table = l_table
         and coalesce(c.release_id, '~') = coalesce(in_release_id, '~')
         and coalesce(c.base_release_id, '~') = coalesce(in_base_release_id, '~');
      if l_snapshot_count >= 20 then
         raise_application_error(-20116, 'ADS history already holds 20 copies: ' || l_table);
      end if;
      insert into dw_ads_snapshot (calc_id, output_table, result_rows)
      values (l_calc_id, l_table, l_count);
      l_hist_table := dbms_assert.simple_sql_name(l_table || '_HIST');
      l_sql := 'insert into ' || l_hist_table
         || ' select :1, t.* from ' || dbms_assert.simple_sql_name(l_read_table) || ' t';
      if l_table in ('ADS_RELEASE_DIFF_SUMMARY', 'ADS_RELEASE_DIFF_DETAIL') then
         l_sql := l_sql || ' where old_release_id = :2 and new_release_id = :3';
         execute immediate l_sql using l_calc_id, in_base_release_id, in_release_id;
      elsif l_table = 'ADS_REVIEW_CASE_MONTHLY' then
         execute immediate l_sql using l_calc_id;
      else
         l_sql := l_sql || ' where release_id = :2';
         execute immediate l_sql using l_calc_id, in_release_id;
      end if;
      l_snapshot_rows := sql%rowcount;
      if l_snapshot_rows != l_count then
         raise_application_error(-20117, 'History snapshot row count does not match the result digest: ' || l_table);
      end if;
   end if;
end record_dw_calculation;
/
