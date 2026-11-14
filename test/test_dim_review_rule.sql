-- Name: test_dim_review_rule.sql
-- Purpose: test SCD Type 2 of the review rule dimension: simulate "the 60-day threshold becomes 90 days from July 2020" and check that
--          the old version is kept and closed, the new version becomes current, a rerun changes nothing, the version in effect on a date can be found,
--          and June and July candidates follow the old and new thresholds. Each check prints pass/fail, and any failure raises an error.
--          Everything is rolled back at the end, leaving no test data (the rule dimension returns to its state before the test)
-- Usage: ORACLE_USER=loan_test scripts/run_sql.sh test/test_dim_review_rule.sql; then run the utPLSQL suite
-- Requires: dim_review_rule, load_dim_review_rule, OLTP tables, and review_api deployed;
--           the rule dimension synced once (run_load_dim_review_rule.sql); the warehouse has R47
-- Called by: run manually

create or replace package test_dim_review_rule as
   --%suite(Review rule dimension SCD2)
   --%rollback(manual)

   --%test(Version history, effective dates, and candidate thresholds)
   procedure run_case;
end test_dim_review_rule;
/

create or replace package body test_dim_review_rule as
   procedure run_case is
      l_rule_id loan_oltp.review_rule.rule_id%type;
      l_v1_id loan_oltp.review_rule_version.rule_version_id%type;
      l_v2_id loan_oltp.review_rule_version.rule_version_id%type;
      l_v1_key_before loan_dw.dim_review_rule.rule_version_key%type;
      l_v1_key_after loan_dw.dim_review_rule.rule_version_key%type;
      l_rows_before pls_integer;
      l_rows_after pls_integer;
      l_rows_again pls_integer;
      l_v1_valid_to date;
      l_v1_current loan_dw.dim_review_rule.is_current%type;
      l_v2_valid_to date;
      l_v2_current loan_dw.dim_review_rule.is_current%type;
      l_min_status_oct number;
      l_min_status_aug number;
      l_created_jun pls_integer;
      l_existing_jun pls_integer;
      l_created_jul pls_integer;
      l_jun_min number;
      l_jul_min number;

      procedure check_true(in_ok in boolean, in_name in varchar2) is
         l_expectation ut_expectation;
      begin
         l_expectation := ut.expect(in_ok, in_name);
         l_expectation.to_be_true();
      end check_true;
   begin
      select rule_id
      into l_rule_id
      from loan_oltp.review_rule
      where rule_code = 'DLQ60_ENTRY';
      select rule_version_id
      into l_v1_id
      from loan_oltp.review_rule_version
      where rule_id = l_rule_id and version_no = 1;

      -- 1. Sync once and record version 1's surrogate key and the total row count
      loan_dw.load_dim_review_rule;
      select count(*)
      into l_rows_before
      from loan_dw.dim_review_rule;
      select rule_version_key
      into l_v1_key_before
      from loan_dw.dim_review_rule
      where rule_version_id = l_v1_id;

      -- 2. Simulate a rule change: from 2020-07 the threshold becomes 03 (90+ days, User Guide p.10); add version 2 in OLTP
      insert into loan_oltp.review_rule_version (
         rule_id, version_no, min_delinquency_status, effective_from, rule_desc
      )
      values (
         l_rule_id, 2, 3, date '2020-07-01', 'Test: threshold changed to 90+ days'
      )
      returning rule_version_id into l_v2_id;

      loan_dw.load_dim_review_rule;
      select count(*)
      into l_rows_after
      from loan_dw.dim_review_rule;
      check_true(
         l_rows_after = l_rows_before + 1
         , 'New version added one row (' || l_rows_before || ' → ' || l_rows_after || ')'
      );

      select
         rule_version_key
         , valid_to
         , is_current
      into l_v1_key_after, l_v1_valid_to, l_v1_current
      from loan_dw.dim_review_rule
      where rule_version_id = l_v1_id;
      check_true(
         l_v1_key_after = l_v1_key_before
         , 'The old version row is still there with the same surrogate key (' || l_v1_key_after || ')'
      );
      check_true(
         l_v1_valid_to = date '2020-06-30' and l_v1_current = 'N'
         , 'Old version closed: end date ' || to_char(l_v1_valid_to, 'yyyy-mm-dd')
         || ', current ' || l_v1_current
      );

      select
         valid_to
         , is_current
      into l_v2_valid_to, l_v2_current
      from loan_dw.dim_review_rule
      where rule_version_id = l_v2_id;
      check_true(
         l_v2_valid_to = date '9999-12-31' and l_v2_current = 'Y'
         , 'New version is current: end date ' || to_char(l_v2_valid_to, 'yyyy-mm-dd')
      );

      -- 3. A rerun changes nothing
      loan_dw.load_dim_review_rule;
      select count(*)
      into l_rows_again
      from loan_dw.dim_review_rule;
      check_true(
         l_rows_again = l_rows_after, 'Row count unchanged after rerun (' || l_rows_again || ')'
      );

      -- 4. Find the version in effect on a date
      select min_delinquency_status
      into l_min_status_oct
      from loan_dw.dim_review_rule
      where
         rule_id = l_rule_id
         and date '2019-10-15' between valid_from and valid_to;
      select min_delinquency_status
      into l_min_status_aug
      from loan_dw.dim_review_rule
      where
         rule_id = l_rule_id
         and date '2020-08-15' between valid_from and valid_to;
      check_true(
         l_min_status_oct = 2 and l_min_status_aug = 3
         , 'Threshold in effect on 2019-10-15 is ' || l_min_status_oct
         || ', on 2020-08-15 it is ' || l_min_status_aug
      );

      -- 5. Candidates follow the version in effect that month; identities already delivered must not be added again.
      select count(*) into l_existing_jun
      from loan_oltp.review_candidate c
      inner join loan_dw.dim_loan d
         on
            c.loan_identifier = d.loan_identifier
            and d.release_id = 'R47'
      where
         c.rule_version_id = l_v1_id  -- noqa: RF02
         and c.data_source = 'FRE'
         and c.reporting_month = date '2020-06-01';
      loan_oltp.review_api.generate_candidates(
         'R47', date '2020-06-01', 'DLQ60_ENTRY', l_created_jun
      );
      loan_oltp.review_api.generate_candidates(
         'R47', date '2020-07-01', 'DLQ60_ENTRY', l_created_jul
      );
      select max(drr.min_delinquency_status)
      into l_jun_min
      from loan_oltp.review_candidate rcd
      inner join loan_dw.dim_review_rule drr
         on rcd.rule_version_id = drr.rule_version_id
      where rcd.reporting_month = date '2020-06-01';
      select max(drr.min_delinquency_status)
      into l_jul_min
      from loan_oltp.review_candidate rcd
      inner join loan_dw.dim_review_rule drr
         on rcd.rule_version_id = drr.rule_version_id
      where rcd.reporting_month = date '2020-07-01';
      check_true(
         l_created_jun + l_existing_jun = 108 and l_created_jul > 0
         and l_jun_min = 2 and l_jul_min = 3
         , 'June candidates ' || (l_created_jun + l_existing_jun) || ' by threshold ' || l_jun_min
         || ', July candidates ' || l_created_jul || ' by threshold ' || l_jul_min
      );

      rollback;
   end run_case;
end test_dim_review_rule;
/
