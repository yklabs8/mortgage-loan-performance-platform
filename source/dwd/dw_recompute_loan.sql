-- dw_recompute_loan.sql
-- Dw recompute loan. See docs/metric_definitions.md for analytical definitions.
create table dw_recompute_loan (
   release_id varchar2(10) not null
   , base_release_id varchar2(10) not null
   , loan_identifier varchar2(12) not null
   , change_kind varchar2(10) not null
   , constraint dw_recompute_loan_pk primary key (release_id, loan_identifier)
   , constraint dw_recompute_loan_kind_ck check (
      change_kind in ('NEW', 'CHANGED', 'REMOVED')
   )
);

-- noqa: disable=LT05
comment on table dw_recompute_loan is 'Affected loans for targeted recomputation relative to a base release. Compare only analytical inputs: origination year and quarter, first payment date, reporting month, delinquency status, exit code and date, modification flag, and agency. Other source corrections do not require summary recomputation.';
comment on column dw_recompute_loan.release_id is 'New release';
comment on column dw_recompute_loan.base_release_id is 'Base release: copy summary results for unaffected loans';
comment on column dw_recompute_loan.loan_identifier is 'Loan identifier';
comment on column dw_recompute_loan.change_kind is 'NEW = only in the new release; CHANGED = analytical inputs changed, including added months; REMOVED = only in the baseline';
-- noqa: enable=LT05
