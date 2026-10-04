# Loan-Review System (OLTP) Design

A proposed business system for manually reviewing loans flagged by rules. In the design, it would read warehouse data to select candidates and record the review process in separate OLTP tables.

Current stage: this repository contains the 13-table model and ER diagram. It does not contain runnable OLTP tables, triggers, procedures, or an application.

## 1. Where the business process comes from

This workflow is a simplified demonstration designed for this project; it is not a bank operating procedure. Its design uses two patterns:

- **Case management:** a case has a status, an assignee, notes, and a change history.
- **Separate preparation and decision:** an Analyst records a review; a Manager makes the decision. This is the intended role split, not a claim that it represents a real institution's policy.

The proposed candidate rule compares successive monthly delinquency statuses and selects loans that newly reach 60 or more days delinquent. The monthly file provides the status field; the threshold is this project's proposed rule. Candidate selection is not implemented in this repository.

## 2. Business process

```
Planned: select loans that newly reach 60+ days delinquent (review_candidate)
  → a review case is opened for a candidate (risk_review_case, status OPEN)
  → a Manager assigns the case to an Analyst (case_assignment, status ASSIGNED)
  → the Analyst adds notes and the basis for a judgment (case_annotation, status IN_REVIEW)
  → the Manager decides: close (CLOSED), or escalate (ESCALATED → closed later)
  → after closure, a Manager may reopen a case for further review (CLOSED → IN_REVIEW)
Planned: record every status change in case_status_history
```

Two proposed roles: the **Analyst** reviews cases and writes notes; the **Manager** assigns cases and makes decisions.

## 3. Entity-relationship model

![OLTP entity-relationship model](img/oltp_er.png)

The diagram shows the 13 proposed tables and their columns. PK = primary key, FK = foreign key, UK = unique key, `*` = mandatory (NOT NULL). Crow's-foot notation: `|` one, `o` zero (optional), `<` many. Where a table has several foreign keys to the same table, the line is labeled with the column (for example `assignee` and `assigned_by`).

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

- **Third normal form (3NF):** the proposed model separates roles, status labels, and rule parameters from cases rather than repeating them on each case.
- **Audit history:** the design has separate assignment, note, decision, and status-history tables. The future implementation must enforce the intended append-only behavior.
- **Versioned rules:** the design gives thresholds a version and records the selecting version on each candidate.
- **Status transitions:** a transition table lists allowed changes. A future trigger must enforce those rows.
- **Stable loan reference:** a candidate uses data source, loan identifier, and source release rather than a warehouse-generated key. The design retains an earlier candidate when a later release corrects that loan.

## 6. Limitations

- It is a demonstration of a review process, not any bank's actual procedure.
- It covers review and decision only: borrower contact and workout evaluation are out of scope.
- Users and roles are demo data; there is no workload balancing or deadline (SLA) tracking.

## 7. Next steps

- Implement and test the proposed tables, constraints, indexes, triggers, and procedures in a later milestone.
- Reconcile this diagram with the implementation when those files are published.
