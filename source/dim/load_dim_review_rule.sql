-- Name: load_dim_review_rule.sql
-- Purpose: create the procedure load_dim_review_rule, which syncs OLTP review rules into dim_review_rule (SCD Type 2).
--          Step 1: insert one row for each version new in OLTP, initially treated as the latest (end date 9999-12-31);
--          Step 2: order each rule's versions by effective date and recompute each version's end date (the day before the next version) and current flag,
--                  which "closes" versions replaced by newer ones; rule code and name are overwritten with current OLTP values (Type 1).
--          Old version rows are never deleted. Reruns give the same result. Does not commit; the caller commits (run_load_dim_review_rule.sql)
--          Each run reads all OLTP rules (there are only a few)
-- Requires: dim_review_rule, review_rule, review_rule_version exist
-- Called by: source/dim/run_load_dim_review_rule.sql; test/test_dim_review_rule.sql

create or replace procedure load_dim_review_rule is
begin
   -- Step 1: insert one row per new version
   insert into dim_review_rule (
      rule_version_id
      , rule_id
      , rule_code
      , rule_name
      , version_no
      , min_delinquency_status
      , rule_desc
      , valid_from
      , valid_to
      , is_current
   )
   select
      rrv.rule_version_id
      , rrv.rule_id
      , rrl.rule_code
      , rrl.rule_name
      , rrv.version_no
      , rrv.min_delinquency_status
      , rrv.rule_desc
      , rrv.effective_from as valid_from
      -- The latest version ends 9999-12-31 (see the comment on dim_review_rule.valid_to)
      , date '9999-12-31' as valid_to
      , 'Y' as is_current
   from loan_oltp.review_rule_version rrv
   inner join loan_oltp.review_rule rrl
      on rrv.rule_id = rrl.rule_id
   where not exists (
      select 1
      from dim_review_rule drr
      where drr.rule_version_id = rrv.rule_version_id
   );

   -- Step 2: recompute end dates and current flags and sync Type 1 attributes; only rows whose values really changed are updated
   merge into dim_review_rule t
   using (
      select
         rrv.rule_version_id
         , rrl.rule_code
         , rrl.rule_name
         , rrv.min_delinquency_status
         , rrv.rule_desc
         , rrv.effective_from as valid_from
         -- The day before the next version takes effect; 9999-12-31 if there is no next version
         , coalesce(
            lead(rrv.effective_from) over (
               partition by rrv.rule_id
               order by rrv.effective_from, rrv.version_no
            ) - 1
            , date '9999-12-31'
         ) as valid_to
         , case
            when
               row_number() over (
                  partition by rrv.rule_id
                  order by rrv.effective_from desc, rrv.version_no desc
               ) = 1
               then 'Y'
            else 'N'
         end as is_current
      from loan_oltp.review_rule_version rrv
      inner join loan_oltp.review_rule rrl
         on rrv.rule_id = rrl.rule_id
   ) s
      on (t.rule_version_id = s.rule_version_id)
   when matched then
      update
         set
            rule_code = s.rule_code
            , rule_name = s.rule_name
            , min_delinquency_status = s.min_delinquency_status
            , rule_desc = s.rule_desc
            , valid_from = s.valid_from
            , valid_to = s.valid_to
            , is_current = s.is_current
      where
         t.rule_code != s.rule_code
         or t.rule_name != s.rule_name
         or t.min_delinquency_status != s.min_delinquency_status
         or t.rule_desc != s.rule_desc
         or t.valid_from != s.valid_from
         or t.valid_to != s.valid_to
         or t.is_current != s.is_current;
end load_dim_review_rule;
/
