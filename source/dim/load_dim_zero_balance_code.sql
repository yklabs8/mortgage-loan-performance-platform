-- load_dim_zero_balance_code.sql
-- Load dim zero balance code. See docs/metric_definitions.md for analytical definitions.
merge into dim_zero_balance_code t
using (
   select
      'FRE' as data_source
      , '01' as zero_balance_code
      , 'Prepaid or Matured (Voluntary Payoff)' as zero_balance_desc
      , 'PREPAID' as exit_state
      , 10 as exit_state_order
   from dual
   union all
   select
      'FRE' as data_source
      , '02' as zero_balance_code
      , 'Third Party Sale' as zero_balance_desc
      , 'LIQUIDATED' as exit_state
      , 11 as exit_state_order
   from dual
   union all
   select
      'FRE' as data_source
      , '03' as zero_balance_code
      , 'Short Sale or Charge Off' as zero_balance_desc
      , 'LIQUIDATED' as exit_state
      , 11 as exit_state_order
   from dual
   union all
   select
      'FRE' as data_source
      , '09' as zero_balance_code
      , 'REO Disposition' as zero_balance_desc
      , 'LIQUIDATED' as exit_state
      , 11 as exit_state_order
   from dual
   union all
   select
      'FRE' as data_source
      , '15' as zero_balance_code
      , 'Whole Loan sales' as zero_balance_desc
      , 'LOAN_SALE' as exit_state
      , 12 as exit_state_order
   from dual
   union all
   select
      'FRE' as data_source
      , '16' as zero_balance_code
      , 'Reperforming loan securitizations' as zero_balance_desc
      , 'LOAN_SALE' as exit_state
      , 12 as exit_state_order
   from dual
   union all
   select
      'FRE' as data_source
      , '96' as zero_balance_code
      , 'Confirmed Underwriting Defect or Major Servicing Defect '
      || 'prior to credit event' as zero_balance_desc
      , 'DEFECT' as exit_state
      , 13 as exit_state_order
   from dual

) s
   on (
      t.data_source = s.data_source
      and t.zero_balance_code = s.zero_balance_code
   )
when matched then
   update set
      zero_balance_desc = s.zero_balance_desc
      , exit_state = s.exit_state
      , exit_state_order = s.exit_state_order
when not matched then
   insert (
      data_source
      , zero_balance_code
      , zero_balance_desc
      , exit_state
      , exit_state_order
   )
   values (
      s.data_source
      , s.zero_balance_code
      , s.zero_balance_desc
      , s.exit_state
      , s.exit_state_order
   );

commit;
