-- Convert new-layout monthly records into the fact exchange stage.
create or replace procedure load_dwd_loan_monthly_perf(
   in_release_id in varchar2
) is
   l_ods_rows pls_integer;
   l_inserted pls_integer;
begin
   insert into dwd_loan_monthly_perf_stage (
      loan_identifier
      , monthly_reporting_period
      , current_loan_delinquency_status
      , data_source
      , release_id
      , loan_key
      , period_date_key
   )
   select
      loan_identifier
      , to_date(monthly_reporting_period, 'YYYYMM') as monthly_reporting_period
      , current_loan_delinquency_status
      , 'FRE' as data_source
      , release_id
      , (
         select dl.loan_key
         from dim_loan dl
         where
            dl.release_id = ods_perf.release_id
            and dl.loan_identifier = ods_perf.loan_identifier
      ) as loan_key
      , to_number(
         to_char(to_date(monthly_reporting_period, 'YYYYMM'), 'YYYYMMDD')
      ) as period_date_key
   from ods_perf
   where release_id = in_release_id;
   l_inserted := sql%rowcount;

   select count(*)
   into l_ods_rows
   from ods_perf
   where release_id = in_release_id;
   if l_inserted = 0 or l_inserted != l_ods_rows then
      raise_application_error(
         -20001
         , 'stage row count mismatch: inserted ' || l_inserted
         || ', ODS ' || l_ods_rows
      );
   end if;
end load_dwd_loan_monthly_perf;
/
