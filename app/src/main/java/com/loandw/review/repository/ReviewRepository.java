package com.loandw.review.repository;

import java.sql.Types;
import java.time.LocalDate;
import java.util.List;
import org.springframework.jdbc.core.simple.JdbcClient;
import org.springframework.stereotype.Repository;
@Repository
public class ReviewRepository {

    
    private static final int LIST_LIMIT = 200;

    private final JdbcClient jdbc;
    public ReviewRepository(JdbcClient jdbc) {
        this.jdbc = jdbc;
    }

    
    public record CandidateRow(long candidateId, String dataSource, String loanIdentifier,
                               LocalDate reportingMonth, String delinquencyStatus, String sourceReleaseId,
                               String ruleCode, int versionNo) {
    }
    
    public List<CandidateRow> candidates(String loanIdentifier) {
        return jdbc.sql("""
                select c.candidate_id, c.data_source, c.loan_identifier, c.reporting_month,
                   c.delinquency_status, c.source_release_id, rl.rule_code, v.version_no
                from review_candidate c
                inner join review_rule_version v on c.rule_version_id = v.rule_version_id
                inner join review_rule rl on v.rule_id = rl.rule_id
                where :loan is null or c.loan_identifier = :loan
                order by c.reporting_month desc, c.candidate_id
                fetch first :limit rows only
                """)
            .param("loan", blankToNull(loanIdentifier), Types.VARCHAR)
            .param("limit", LIST_LIMIT)
            .query(CandidateRow.class)
            .list();
    }
    private static String blankToNull(String s) {
        return s == null || s.isBlank() ? null : s.trim();
    }
}
