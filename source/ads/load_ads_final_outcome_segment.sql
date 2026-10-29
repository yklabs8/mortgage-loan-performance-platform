-- load_ads_final_outcome_segment.sql
-- Load ads final outcome segment. See docs/metric_definitions.md for analytical definitions.
create or replace procedure load_ads_final_outcome_segment(
   in_release_id in varchar2
) is
   l_bad pls_integer;
begin
   select count(*) into l_bad
   from dws_perf_loan_td p
   inner join dim_loan d
      on
         p.release_id = d.release_id
         and p.loan_identifier = d.loan_identifier
   left join dim_zero_balance_code z
      on
         d.data_source = z.data_source
         and p.zero_balance_code = z.zero_balance_code
   where
      p.release_id = in_release_id  -- noqa: RF02,RF03
      and p.zero_balance_code is not null
      and z.exit_state is null;
   if l_bad > 0 then
      raise_application_error(-20049, 'Unmapped zero-balance code in final outcomes');
   end if;

   delete from ads_final_outcome_segment
   where release_id = in_release_id;
   insert into ads_final_outcome_segment (
      origination_year, segment_type, segment_value, final_state
      , loan_count, release_id
   )
   select
      d.origination_year
      , seg.segment_type
      , seg.segment_value
      , coalesce(z.exit_state, 'ACTIVE') as final_state
      , count(*) as loan_count
      , in_release_id as release_id  -- noqa: RF02,RF03
   from dws_perf_loan_td p
   inner join dim_loan d
      on
         p.release_id = d.release_id
         and p.loan_identifier = d.loan_identifier
   inner join v_loan_segment seg
      on
         d.release_id = seg.release_id
         and d.loan_identifier = seg.loan_identifier
   left join dim_zero_balance_code z
      on
         d.data_source = z.data_source
         and p.zero_balance_code = z.zero_balance_code
   where p.release_id = in_release_id  -- noqa: RF02,RF03
   group by
      d.origination_year, seg.segment_type, seg.segment_value
      , coalesce(z.exit_state, 'ACTIVE');
end load_ads_final_outcome_segment;
/
