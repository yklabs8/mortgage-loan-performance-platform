merge into review_rule t
using (
   select
      'DLQ60_ENTRY' as rule_code
      , 'First entry into 60+ day delinquency this month' as rule_name
   from dual
) s
   on (t.rule_code = s.rule_code)
when not matched then
   insert (rule_code, rule_name) values (s.rule_code, s.rule_name);

merge into review_rule_version t
using (
   select
      rule_id
      , 1 as version_no
      , 2 as min_delinquency_status
      , date '1999-01-01' as effective_from
      , 'Prior month below 02 or absent; this month 02+ or RA: candidate'
      || ' (User Guide p.10 status codes; RA follows metric definition 1)'
         as rule_desc
   from review_rule
   where rule_code = 'DLQ60_ENTRY'
) s
   on (t.rule_id = s.rule_id and t.version_no = s.version_no)
when not matched then
   insert (
      rule_id, version_no, min_delinquency_status, effective_from, rule_desc
   )
   values (
      s.rule_id
      , s.version_no
      , s.min_delinquency_status
      , s.effective_from
      , s.rule_desc
   );

commit;
