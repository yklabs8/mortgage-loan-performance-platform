-- compare_releases.sql
-- Compare releases. See docs/metric_definitions.md for analytical definitions.
create or replace procedure compare_releases(
   in_old_release_id in varchar2
   , in_new_release_id in varchar2
) is
   l_old_dim_rows pls_integer;
   l_old_dwd_rows pls_integer;
   l_new_dim_rows pls_integer;
   l_new_dwd_rows pls_integer;
begin
   if in_old_release_id = in_new_release_id then
      raise_application_error(-20014, 'Base and new release must differ');
   end if;

   select count(*)
   into l_old_dim_rows
   from dim_loan
   where release_id = in_old_release_id;
   select count(*)
   into l_old_dwd_rows
   from dwd_loan_monthly_perf
   where release_id = in_old_release_id;
   select count(*)
   into l_new_dim_rows
   from dim_loan
   where release_id = in_new_release_id;
   select count(*)
   into l_new_dwd_rows
   from dwd_loan_monthly_perf
   where release_id = in_new_release_id;

   if l_old_dim_rows = 0 or l_old_dwd_rows = 0 then
      raise_application_error(
         -20014, 'Old release has incomplete DIM/DWD data: ' || in_old_release_id
      );
   end if;
   if l_new_dim_rows = 0 or l_new_dwd_rows = 0 then
      raise_application_error(
         -20014, 'New release has incomplete DIM/DWD data: ' || in_new_release_id
      );
   end if;

   delete from ads_release_diff_summary
   where
      old_release_id = in_old_release_id
      and new_release_id = in_new_release_id;
   delete from ads_release_diff_detail
   where
      old_release_id = in_old_release_id
      and new_release_id = in_new_release_id;

   compare_dim_loan(in_old_release_id, in_new_release_id);
   compare_dwd_loan_monthly_perf(in_old_release_id, in_new_release_id);
   commit;
   exception
      when others then
         rollback;
         raise;
end compare_releases;
/
