-- gather_dw_stats.sql
-- GATHER AUTO collects missing or stale optimizer statistics (Oracle SQL Tuning Guide, chapter 13). It commits implicitly and must run after the load transaction commits.
create or replace procedure gather_dw_stats is
begin
   dbms_stats.gather_schema_stats(ownname => user, options => 'GATHER AUTO');
end gather_dw_stats;
/
