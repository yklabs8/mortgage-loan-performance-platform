package com.loandw.review;

import org.springframework.jdbc.core.simple.JdbcClient;

/** Loan IDs reserved for tests; business tests insert candidates directly instead of calling the candidate generation reference procedure. */
final class CandidateFixtures {
    static long insert(JdbcClient jdbc, String loan) {
        jdbc.sql("""
            insert into review_candidate (rule_version_id, data_source, loan_identifier,
                reporting_month, delinquency_status, source_release_id, candidate_source)
            values (1, 'FRE', :loan, date '2020-06-01', '02', 'R47', 'TEST')
            """).param("loan", loan).update();
        return jdbc.sql("select candidate_id from review_candidate where loan_identifier=:loan")
            .param("loan", loan).query(Long.class).single();
    }
}
