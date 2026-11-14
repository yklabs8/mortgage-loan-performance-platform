-- Name: run_load_dim_review_rule.sql
-- Purpose: call load_dim_review_rule to sync OLTP review rules into dim_review_rule, then commit and list the result
-- Usage: scripts/run_sql.sh source/dim/run_load_dim_review_rule.sql
-- Requires: load_dim_review_rule exists; OLTP reference data loaded (oltp_seed.sql)
-- Called by: run manually after an OLTP rule changes

begin
   load_dim_review_rule;
   commit;
end;
/

-- Show dates with four-digit years: the default DD-MON-RR format shows 9999-12-31 as 31-DEC-99, which looks like 1999
select
   rule_code
   , version_no
   , min_delinquency_status
   , is_current
   , to_char(valid_from, 'yyyy-mm-dd') as valid_from
   , to_char(valid_to, 'yyyy-mm-dd') as valid_to
from dim_review_rule
order by rule_code asc, version_no asc;
