-- Merge loan identity, first payment month, and origination quarter from the new-layout ODS.
create or replace procedure load_dim_loan(
   in_release_id in varchar2
) is
   l_ods_rows pls_integer;
   l_merged pls_integer;
   l_dim_rows pls_integer;
begin
   merge into dim_loan t
   using (
      select
         to_date(first_payment_date, 'YYYYMM') as first_payment_date
         , loan_identifier
         , case
            when substr(loan_identifier, 2, 2) = '99' then 1999
            else 2000 + to_number(substr(loan_identifier, 2, 2))
         end as origination_year
         , to_number(substr(loan_identifier, 5, 1)) as origination_quarter
         , release_id
         , 'FRE' as data_source
      from ods_orig
      where release_id = in_release_id
   ) s
      on (
         t.release_id = s.release_id
         and t.loan_identifier = s.loan_identifier
      )
   when matched then
      update set
         first_payment_date = s.first_payment_date
         , origination_year = s.origination_year
         , origination_quarter = s.origination_quarter
         , data_source = s.data_source
   when not matched then
      insert (
         first_payment_date
         , loan_identifier
         , origination_year
         , origination_quarter
         , release_id
         , data_source
      )
      values (
         s.first_payment_date
         , s.loan_identifier
         , s.origination_year
         , s.origination_quarter
         , s.release_id
         , s.data_source
      );
   l_merged := sql%rowcount;

   select count(*)
   into l_ods_rows
   from ods_orig
   where release_id = in_release_id;
   select count(*)
   into l_dim_rows
   from dim_loan
   where release_id = in_release_id;
   if l_merged = 0 or l_merged != l_ods_rows or l_dim_rows != l_ods_rows then
      raise_application_error(
         -20001
         , 'dim_loan row count mismatch: merged ' || l_merged
         || ', dimension ' || l_dim_rows
         || ', ODS ' || l_ods_rows
      );
   end if;
end load_dim_loan;
/
