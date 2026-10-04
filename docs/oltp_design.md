# Loan-Review System (OLTP) Design

A business system for manually reviewing loans flagged by rules. It reads from the data warehouse (to select candidate loans) and records the review process in its own normalized database; it never writes to the warehouse.

Current stage: the conceptual, logical, and relational models are complete; tables, constraints, triggers, and stored procedures are implemented in later milestones.

## 1. Where the business process comes from

Banks do not publish their internal review procedures, so the workflow was designed for this project as a simplified demonstration; it is not any bank's actual operating procedure. It combines two widely used patterns:

- **Case management:** a case with a status, an owner, notes, and a change history. The same structure appears in common case-management systems, for example Salesforce's Case, CaseComment, CaseHistory, and CaseStatus objects.
- **The four-eyes principle (maker-checker):** one person prepares a review, a second, independent person approves it, a standard control in financial systems such as credit approval.

The trigger, a loan that newly reaches 60+ days delinquent, comes directly from the delinquency status in the Freddie Mac monthly performance data. References to specific regulatory and servicing rules will be added after they are checked against the original texts.

## 2. Business process

```
The system selects loans that newly reach 60+ days delinquent (review_candidate)
  → a review case is opened for a candidate (risk_review_case, status OPEN)
  → a Manager assigns the case to an Analyst (case_assignment, status ASSIGNED)
  → the Analyst adds notes and the basis for a judgment (case_annotation, status IN_REVIEW)
  → the Manager decides: close (CLOSED), or escalate (ESCALATED → closed later)
Every status change is recorded in case_status_history
```

Two roles: the **Analyst** reviews cases and writes notes; the **Manager** assigns cases and makes decisions.

## 3. Entity-relationship model

![OLTP entity-relationship model](img/oltp_er.png)

All 13 tables with every column. PK = primary key, FK = foreign key, UK = unique key, `*` = mandatory (NOT NULL). Crow's-foot notation: `|` one, `o` zero (optional), `<` many. Where a table has several foreign keys to the same table, the line is labeled with the column (for example `assignee` and `assigned_by`).

## 4. Logical and relational model (13 tables)

| Table | Primary key | Business unique key | Description |
|---|---|---|---|
| `app_user` | user_id | username | Application user |
| `app_role` | role_id | role_code | Reference: ANALYST, MANAGER |
| `user_role` | (user_id, role_id) | — | Users and roles are many-to-many |
| `review_rule` | rule_id | rule_code | Review rule |
| `review_rule_version` | rule_version_id | (rule_id, version_no) | Rule parameters; changing a rule adds a new version instead of overwriting |
| `review_candidate` | candidate_id | (rule_version_id, data_source, loan_identifier, reporting_month) | Candidate selected from the warehouse, with its data source and release |
| `case_status` | status_code | — | Reference: OPEN, ASSIGNED, IN_REVIEW, ESCALATED, CLOSED |
| `case_status_transition` | (from_status, to_status) | — | Allowed status changes |
| `risk_review_case` | case_id | case_number; candidate_id | Review case; at most one per candidate |
| `case_assignment` | assignment_id | — | Assignment records, append-only |
| `case_annotation` | annotation_id | — | Notes |
| `case_status_history` | status_event_id | — | Status history, append-only |
| `review_decision` | decision_id | — | Manager decisions, append-only |

## 5. Design rationale

- **Third normal form (3NF):** every non-key column depends only on its table's primary key. A user's roles live in `user_role` (one user can have several roles); status names live once in `case_status`, not on every case.
- **Every action is auditable:** assignments, notes, decisions, and status history are separate append-only tables, so who did what and when is never overwritten.
- **Versioned rules:** thresholds live in `review_rule_version`; a candidate records the version that selected it, so changing a rule never changes the basis of earlier candidates.
- **Status machine as data:** allowed status changes are rows in `case_status_transition`, checked by a trigger, so a case cannot jump from OPEN to CLOSED without review.
- **Business keys, not surrogate keys:** a candidate refers to a loan by data source + loan number + source release, not by the warehouse surrogate key, which is regenerated on every reload. When a new release corrects a loan, the old candidate is kept as an audit record.

## 6. Limitations

- It is a demonstration of a review process, not any bank's actual procedure.
- It covers review and decision only: borrower contact and workout evaluation are out of scope.
- Users and roles are demo data; there is no workload balancing or deadline (SLA) tracking.

## 7. Next steps

- Draw the Enterprise, Logical, and Relational models in Oracle SQL Developer Data Modeler and generate the DDL from the model
- Implement tables, constraints, indexes, triggers (status-change checks, automatic status history), and stored procedures, and test each of them
