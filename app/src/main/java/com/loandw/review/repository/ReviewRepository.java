package com.loandw.review.repository;

import java.math.BigDecimal;
import java.sql.Types;
import java.time.LocalDate;
import java.time.LocalDateTime;
import java.util.List;
import java.util.Optional;

import org.springframework.dao.DataAccessException;
import org.springframework.dao.DataIntegrityViolationException;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.jdbc.support.GeneratedKeyHolder;
import org.springframework.jdbc.core.simple.JdbcClient;
import org.springframework.stereotype.Repository;

/**
 * Reads and writes the review system (OLTP) and the warehouse.
 * <ul>
 *   <li>All SQL uses parameters (:name or ?); user input is never concatenated into SQL strings, preventing SQL injection</li>
 *   <li>The four business write operations use parameterized DML; candidate generation keeps the review_api reference implementation</li>
 *   <li>Role and status rules and transactions are owned by the service layer; database constraints and audit triggers are the safety net</li>
 * </ul>
 */
@Repository
public class ReviewRepository {

    
    private static final int LIST_LIMIT = 200;

    private final JdbcClient jdbc;
    private final JdbcTemplate jdbcTemplate;

    public ReviewRepository(JdbcClient jdbc, JdbcTemplate jdbcTemplate) {
        this.jdbc = jdbc;
        this.jdbcTemplate = jdbcTemplate;
    }

    
    public record CandidateRow(long candidateId, String dataSource, String loanIdentifier,
                               LocalDate reportingMonth, String delinquencyStatus, String sourceReleaseId,
                               String ruleCode, int versionNo, Long caseId, String caseNumber) {
    }

    /** One row of the case list. */
    public record CaseRow(long caseId, String caseNumber, String currentStatus, String statusName,
                          String dataSource, String loanIdentifier, LocalDate reportingMonth, String openedBy,
                          String assignee, LocalDateTime openedAt, LocalDateTime closedAt) {
    }

    /** Header of the case detail. */
    public record CaseDetail(long caseId, String caseNumber, String currentStatus, String statusName,
                             String isTerminal, long candidateId, String dataSource, String loanIdentifier,
                             LocalDate reportingMonth, String delinquencyStatus, String sourceReleaseId, String ruleCode, int versionNo,
                             int minDelinquencyStatus, String openedBy, String assignee,
                             LocalDateTime openedAt, LocalDateTime closedAt) {
    }

    /** Origination information from the delivered evidence. */
    public record LoanInfo(BigDecimal classicFico, BigDecimal originalUpb, BigDecimal originalLoanToValueLtv,
                           BigDecimal originalInterestRate, String propertyState, int originationYear,
                           LocalDate firstPaymentDate) {
    }

    /** Monthly performance from the delivered evidence. */
    public record MonthRow(LocalDate monthlyReportingPeriod, String currentLoanDelinquencyStatus,
                           BigDecimal currentActualUpb, BigDecimal currentInterestRate, String zeroBalanceCode,
                           LocalDate zeroBalanceEffectiveDate, String modificationFlag, boolean missing) {
    }

    /** Status history, notes, decisions: "who did what and when". */
    public record ActivityRow(LocalDateTime happenedAt, String userName, String kind, String fromCode,
                              String toCode, String text) {
    }

    /** One row of the monthly review report (warehouse report view rpt_review_case_monthly); average days to close is empty when nothing is closed. */
    public record ReportRow(LocalDate openedMonth, String dataSource, String ruleCode, String currentStatus,
                            String statusName, long caseCount, long escalatedCount, long reopenedCount,
                            long closedCount,
                            BigDecimal avgDaysToClose) {
    }

    /** Totals of the monthly review report and how fresh the report data is (how far the latest extraction read). */
    public record ReportTotal(long caseCount, long escalatedCount, long reopenedCount, long closedCount,
                              BigDecimal avgDaysToClose,
                              LocalDateTime dataUntil) {
    }

    /** One option of a drop-down list. */
    public record Option(String value, String label) {
    }

    // ---------- Users ----------

    public long userId(String username) {
        return jdbc.sql("select user_id from app_user where username = :username")
            .param("username", username)
            .query(Long.class)
            .single();
    }

    /** Analysts who can be assigned cases (active, with the ANALYST role). */
    public List<Option> analysts() {
        return jdbc.sql("""
                select to_char(u.user_id) as value, u.full_name as label
                from app_user u
                inner join user_role ur on u.user_id = ur.user_id
                inner join app_role r on ur.role_id = r.role_id
                where r.role_code = 'ANALYST' and u.is_active = 'Y'
                order by u.full_name
                """)
            .query(Option.class)
            .list();
    }

    /** Published (DW) candidates paged by stable business key; the cursor holds the full sort key. */
    public List<CandidateRow> candidates(String loan) {
        return candidates(loan, null, 50, null);
    }

    public List<CandidateRow> candidates(String loan, LocalDate month, int size, String after) {
        String[] cursor = after == null ? new String[]{"0001-01-01", "", "", "0"} : after.split("~", -1);
        if (cursor.length != 4 || size < 1 || size > 100) {
            throw new IllegalArgumentException("Invalid paging parameter");
        }
        LocalDate cursorMonth = LocalDate.parse(cursor[0]);
        long rule = Long.parseLong(cursor[3]);
        if (after != null && (cursor[1].length() > 3 || cursor[2].length() > 12 || rule < 1)) {
            throw new IllegalArgumentException("Invalid paging cursor");
        }
        return jdbc.sql("""
            select c.candidate_id, c.data_source, c.loan_identifier, c.reporting_month,
                c.delinquency_status, c.source_release_id, rl.rule_code, v.version_no,
                rc.case_id, rc.case_number
            from review_candidate c
            inner join review_rule_version v on c.rule_version_id=v.rule_version_id
            inner join review_rule rl on v.rule_id=rl.rule_id
            left join risk_review_case rc on rc.candidate_id=c.candidate_id
            where c.candidate_source='DW'
                and (:loan is null or c.loan_identifier=:loan)
                and (:month is null or c.reporting_month=:month)
                and (:firstPage=1 or c.reporting_month > :cm
                    or (c.reporting_month=:cm and c.data_source > :ds)
                    or (c.reporting_month=:cm and c.data_source=:ds and c.loan_identifier > :li)
                    or (c.reporting_month=:cm and c.data_source=:ds and c.loan_identifier=:li
                        and c.rule_version_id > :rv))
            order by c.reporting_month, c.data_source, c.loan_identifier, c.rule_version_id
            fetch first :limit rows only
            """).param("loan", blankToNull(loan), Types.VARCHAR)
            .param("month", month, Types.DATE).param("firstPage", after == null ? 1 : 0)
            .param("cm", cursorMonth).param("ds", cursor[1], Types.VARCHAR)
            .param("li", cursor[2], Types.VARCHAR).param("rv", rule).param("limit", size + 1)
            .query(CandidateRow.class).list();
    }

    public String candidateCursor(long id) {
        return jdbc.sql("""
            select to_char(reporting_month, 'YYYY-MM-DD') || '~' || data_source || '~'
                || loan_identifier || '~' || rule_version_id from review_candidate where candidate_id=:id
            """).param("id", id).query(String.class).single();
    }

    public record EvidenceRef(Long evidenceId, Long latestEvidenceId) { }

    public EvidenceRef caseEvidence(long id) {
        return jdbc.sql("""
            select rc.evidence_id, c.latest_evidence_id from risk_review_case rc
            inner join review_candidate c on c.candidate_id=rc.candidate_id where rc.case_id=:id
            """).param("id", id).query(EvidenceRef.class).single();
    }

    public record Evidence(long evidenceId, String deliveryId, String contentSha256,
        String sourceReleaseId, String ruleCode, int versionNo, int minDelinquencyStatus,
        String currentLoanDelinquencyStatus, String previousDelinquencyStatus,
        BigDecimal currentActualUpb, BigDecimal currentInterestRate, String zeroBalanceCode,
        LocalDate zeroBalanceEffectiveDate, String modificationFlag) { }

    public Optional<Evidence> evidence(Long id) {
        if (id == null) return Optional.empty();
        return jdbc.sql("""
            select evidence_id, lower(rawtohex(delivery_id)) as delivery_id, content_sha256,
                source_release_id, rule_code, version_no, min_delinquency_status,
                current_loan_delinquency_status, previous_delinquency_status,
                current_actual_upb, current_interest_rate, zero_balance_code,
                zero_balance_effective_date, modification_flag
            from review_evidence where evidence_id=:id
            """).param("id", id).query(Evidence.class).optional();
    }

    public Optional<CandidateRow> candidate(long id) {
        return jdbc.sql("""
            select c.candidate_id, c.data_source, c.loan_identifier, c.reporting_month,
                c.delinquency_status, c.source_release_id, rl.rule_code, v.version_no,
                rc.case_id, rc.case_number from review_candidate c
            inner join review_rule_version v on v.rule_version_id=c.rule_version_id
            inner join review_rule rl on rl.rule_id=v.rule_id
            left join risk_review_case rc on rc.candidate_id=c.candidate_id
            where c.candidate_id=:id and c.candidate_source='DW'
            """).param("id", id).query(CandidateRow.class).optional();
    }

    public Long latestEvidence(long id) {
        return jdbc.sql("select latest_evidence_id from review_candidate where candidate_id=:id")
            .param("id", id).query(Long.class).single();
    }

    // ---------- Cases ----------

    /** Case list: managers see all; analysts see only cases assigned to them or opened by them. */
    public List<CaseRow> cases(long userId, boolean manager) {
        return jdbc.sql("""
                with last_assign as (
                   select case_id, assignee_user_id,
                      row_number() over (partition by case_id
                         order by assigned_at desc, assignment_id desc) as rn
                   from case_assignment
                )
                select rc.case_id, rc.case_number, rc.current_status, cs.status_name, c.data_source,
                   c.loan_identifier, c.reporting_month, opener.full_name as opened_by,
                   assignee.full_name as assignee,
                   cast(rc.opened_at as date) as opened_at, cast(rc.closed_at as date) as closed_at
                from risk_review_case rc
                inner join case_status cs on rc.current_status = cs.status_code
                inner join review_candidate c on rc.candidate_id = c.candidate_id
                inner join app_user opener on rc.opened_by_user_id = opener.user_id
                left join last_assign la on rc.case_id = la.case_id and la.rn = 1
                left join app_user assignee on la.assignee_user_id = assignee.user_id
                where :manager = 1 or rc.opened_by_user_id = :userId or la.assignee_user_id = :userId
                order by rc.opened_at desc
                fetch first :limit rows only
                """)
            .param("manager", manager ? 1 : 0)
            .param("userId", userId)
            .param("limit", LIST_LIMIT)
            .query(CaseRow.class)
            .list();
    }

    /** Whether this user can see this case: opened by them, or most recently assigned to them (same condition as the case list). */
    public boolean canSee(long caseId, long userId) {
        return jdbc.sql("""
                select count(*)
                from risk_review_case rc
                where rc.case_id = :caseId
                   and (rc.opened_by_user_id = :userId
                      or :userId = (
                         select a.assignee_user_id
                         from case_assignment a
                         where a.case_id = rc.case_id
                         order by a.assigned_at desc, a.assignment_id desc
                         fetch first 1 row only))
                """)
            .param("caseId", caseId)
            .param("userId", userId)
            .query(Integer.class)
            .single() > 0;
    }

    public Optional<CaseDetail> caseDetail(long caseId) {
        return jdbc.sql("""
                with last_assign as (
                   select case_id, assignee_user_id,
                      row_number() over (partition by case_id
                         order by assigned_at desc, assignment_id desc) as rn
                   from case_assignment
                   where case_id = :caseId
                )
                select rc.case_id, rc.case_number, rc.current_status, cs.status_name, cs.is_terminal,
                   c.candidate_id,
                   c.data_source, c.loan_identifier, c.reporting_month, c.delinquency_status,
                   c.source_release_id, rl.rule_code, v.version_no, v.min_delinquency_status,
                   opener.full_name as opened_by, assignee.full_name as assignee,
                   cast(rc.opened_at as date) as opened_at, cast(rc.closed_at as date) as closed_at
                from risk_review_case rc
                inner join case_status cs on rc.current_status = cs.status_code
                inner join review_candidate c on rc.candidate_id = c.candidate_id
                inner join review_rule_version v on c.rule_version_id = v.rule_version_id
                inner join review_rule rl on v.rule_id = rl.rule_id
                inner join app_user opener on rc.opened_by_user_id = opener.user_id
                left join last_assign la on rc.case_id = la.case_id and la.rn = 1
                left join app_user assignee on la.assignee_user_id = assignee.user_id
                where rc.case_id = :caseId
                """)
            .param("caseId", caseId)
            .query(CaseDetail.class)
            .optional();
    }

    public Optional<LoanInfo> loanInfo(Long evidenceId) {
        if (evidenceId == null) return Optional.empty();
        return jdbc.sql("""
            select classic_fico, original_upb, original_loan_to_value_ltv, original_interest_rate,
                property_state, origination_year, first_payment_date
            from review_evidence where evidence_id=:id
            """).param("id", evidenceId).query(LoanInfo.class).optional();
    }

    /** Build the month cells for display only; missing records are marked missing and nothing is written to the database. */
    public List<MonthRow> recentMonths(Long evidenceId, LocalDate untilMonth) {
        if (evidenceId == null) return List.of();
        var actual = jdbc.sql("""
            select monthly_reporting_period, current_loan_delinquency_status, current_actual_upb,
                current_interest_rate, zero_balance_code, zero_balance_effective_date, modification_flag,
                0 as missing from review_evidence_month where evidence_id=:id
            """).param("id", evidenceId).query(MonthRow.class).list();
        return java.util.stream.IntStream.rangeClosed(0, 12).mapToObj(i -> {
            LocalDate month = untilMonth.minusMonths(i);
            return actual.stream().filter(row -> row.monthlyReportingPeriod().equals(month)).findFirst()
                .orElse(new MonthRow(month, null, null, null, null, null, null, true));
        }).toList();
    }

    /**
     * Events on the case in time order. kind is STATUS / ASSIGN / NOTE / DECISION, shown in the interface language;
     * status changes: fromCode and toCode are status codes (fromCode is empty on opening); assignments: text is the assignee;
     * notes: text is the note; decisions: fromCode is the decision type and text the reason. Within the same minute: decisions, assignments, notes, then statuses.
     */
    public List<ActivityRow> activities(long caseId) {
        return jdbc.sql("""
                select happened_at, user_name, kind, from_code, to_code, text
                from (
                   select cast(h.changed_at as date) as happened_at, u.full_name as user_name,
                      'STATUS' as kind, h.from_status as from_code, h.to_status as to_code,
                      cast(null as varchar2(4000)) as text, 4 as sort_key
                   from case_status_history h
                   left join app_user u on h.changed_by_user_id = u.user_id
                   where h.case_id = :caseId
                   union all
                   select cast(a.assigned_at as date), m.full_name, 'ASSIGN', null, null, u.full_name, 2
                   from case_assignment a
                   inner join app_user u on a.assignee_user_id = u.user_id
                   inner join app_user m on a.assigned_by_user_id = m.user_id
                   where a.case_id = :caseId
                   union all
                   select cast(n.created_at as date), u.full_name, 'NOTE', null, null, n.note_text, 3
                   from case_annotation n
                   inner join app_user u on n.author_user_id = u.user_id
                   where n.case_id = :caseId
                   union all
                   select cast(d.decided_at as date), u.full_name, 'DECISION', d.decision_type, null,
                      d.decision_note, 1
                   from review_decision d
                   inner join app_user u on d.decided_by_user_id = u.user_id
                   where d.case_id = :caseId
                )
                order by happened_at, sort_key
                """)
            .param("caseId", caseId)
            .query(ActivityRow.class)
            .list();
    }

    // ---------- Reports (warehouse) ----------

    /**
     * Monthly review report, newest opening month first. The report is recomputed after each incremental extraction (source/dwd/run_cdc_review.sql), so it is not real-time.
     * Reads the read-only report view, never the underlying table.
     */
    public List<ReportRow> reviewReport() {
        return jdbc.sql("""
                select opened_month, data_source, rule_code, current_status, status_name,
                   case_count, escalated_count, reopened_count, closed_count, avg_days_to_close
                from loan_dw.rpt_review_case_monthly
                order by opened_month desc, data_source, rule_code, current_status
                """)
            .query(ReportRow.class)
            .list();
    }

    /** Totals: average days to close = total days / total closed (row averages are not averaged again). */
    public ReportTotal reviewReportTotal() {
        return jdbc.sql("""
                with totals as (
                   select coalesce(sum(case_count), 0) as case_count,
                      coalesce(sum(escalated_count), 0) as escalated_count,
                      coalesce(sum(reopened_count), 0) as reopened_count,
                      coalesce(sum(closed_count), 0) as closed_count,
                      case when sum(closed_count) > 0
                         then round(sum(total_days_to_close) / sum(closed_count), 1) end as avg_days_to_close
                   from loan_dw.rpt_review_case_monthly
                ), last_run as (
                   select cast(max(to_ts) as date) as data_until
                   from loan_dw.etl_cdc_run
                   where source_name = 'REVIEW_CASE'
                )
                select t.case_count, t.escalated_count, t.reopened_count,
                   t.closed_count, t.avg_days_to_close, r.data_until
                from totals t
                cross join last_run r
                """)
            .query(ReportTotal.class)
            .single();
    }

    // ---------- Writes: parameterized DML; candidates keep the reference procedure ----------

    /** Open a case; a missing candidate (foreign key) or an already opened case (unique constraint) becomes a readable message. */
    public long openCase(long candidateId, long userId) {
        try {
            return openCaseCall(candidateId, userId);
        } catch (DataIntegrityViolationException e) {
            throw ReviewApiException.withCause(e, "error.candidate.taken", String.valueOf(candidateId));
        }
    }

    private long openCaseCall(long candidateId, long userId) {
        int allowed = jdbc.sql("""
            select count(*) from review_candidate where candidate_id=:id
                and (candidate_source='TEST' or (candidate_source='DW' and latest_evidence_id is not null))
            """).param("id", candidateId).query(Integer.class).single();
        if (allowed != 1) throw new ReviewApiException("error.candidate.noEvidence");
        var key = new GeneratedKeyHolder();
        jdbcTemplate.update(con -> {
            var statement = con.prepareStatement("""
                insert into risk_review_case (case_number, candidate_id, current_status,
                    opened_by_user_id, updated_by_user_id, evidence_id)
                values ('RRC-' || lpad(risk_review_case_seq.nextval, 6, '0'), ?, 'OPEN', ?, ?,
                    (select latest_evidence_id from review_candidate where candidate_id=?))
                """, new String[]{"CASE_ID"});
            statement.setLong(1, candidateId);
            statement.setLong(2, userId);
            statement.setLong(3, userId);
            statement.setLong(4, candidateId);
            return statement;
        }, key);
        if (key.getKey() == null) throw new ReviewApiException("error.candidate.noEvidence");
        return key.getKey().longValue();
    }

    /** Every update locks the case first and waits at most 3 seconds. */
    public String lockCase(long caseId) {
        try {
            return jdbc.sql("""
                select current_status from risk_review_case where case_id = :id for update wait 3
                """).param("id", caseId).query(String.class).optional()
                .orElseThrow(() -> new ReviewApiException("error.notFound"));
        } catch (DataAccessException e) {
            throw ReviewApiException.from(e);
        }
    }

    public boolean isTerminal(String status) {
        return "Y".equals(jdbc.sql("select is_terminal from case_status where status_code = :status")
            .param("status", status).query(String.class).single());
    }

    public boolean hasRole(long userId, String role) {
        return jdbc.sql("""
            select count(*) from user_role ur
            inner join app_role r on ur.role_id = r.role_id
            where ur.user_id = :id and r.role_code = :role
            """).param("id", userId).param("role", role).query(Integer.class).single() > 0;
    }

    public boolean allowsTransition(String from, String to) {
        return jdbc.sql("""
            select count(*) from case_status_transition where from_status = :fromStatus and to_status = :toStatus
            """).param("fromStatus", from).param("toStatus", to).query(Integer.class).single() > 0;
    }

    public void insertAssignment(long caseId, long assigneeUserId, long managerUserId) {
        write(() -> jdbc.sql("""
            insert into case_assignment (case_id, assignee_user_id, assigned_by_user_id)
            values (:id, :assignee, :manager)
            """).param("id", caseId).param("assignee", assigneeUserId).param("manager", managerUserId).update());
    }

    public void insertAnnotation(long caseId, long userId, String note) {
        write(() -> jdbc.sql("""
            insert into case_annotation (case_id, author_user_id, note_text) values (:id, :author, :note)
            """).param("id", caseId).param("author", userId).param("note", note).update());
    }

    public void insertDecision(long caseId, long managerUserId, String type, String note) {
        write(() -> jdbc.sql("""
            insert into review_decision (case_id, decision_type, decided_by_user_id, decided_as_role, decision_note)
            values (:id, :type, :manager, 'MANAGER', :note)
            """).param("id", caseId).param("type", type).param("manager", managerUserId).param("note", note).update());
    }

    public void updateStatus(long caseId, String status, long userId) {
        write(() -> jdbc.sql("""
            update risk_review_case set current_status = :status, updated_by_user_id = :userId where case_id = :id
            """).param("status", status).param("userId", userId).param("id", caseId).update());
    }

    private void write(Runnable action) {
        try {
            action.run();
        } catch (DataAccessException e) {
            throw ReviewApiException.from(e);
        }
    }

    private static String blankToNull(String s) {
        return s == null || s.isBlank() ? null : s.trim();
    }
}
