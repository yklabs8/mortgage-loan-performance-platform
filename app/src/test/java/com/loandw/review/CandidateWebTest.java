package com.loandw.review;

import static org.assertj.core.api.Assertions.assertThat;
import static org.hamcrest.Matchers.containsString;
import static org.springframework.security.test.web.servlet.request.SecurityMockMvcRequestPostProcessors.user;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.get;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.content;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

import java.sql.Connection;
import java.sql.DriverManager;
import java.time.LocalDate;
import java.util.ArrayList;
import java.util.List;
import java.util.UUID;

import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Tag;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.boot.webmvc.test.autoconfigure.AutoConfigureMockMvc;
import org.springframework.jdbc.core.simple.JdbcClient;
import org.springframework.jdbc.datasource.SingleConnectionDataSource;
import org.springframework.test.context.transaction.AfterTransaction;
import org.springframework.test.web.servlet.MockMvc;
import org.springframework.transaction.annotation.Transactional;

import com.loandw.review.repository.ReviewRepository;
import com.loandw.review.service.ReviewService;

/** Verify the candidate page, pinned evidence, missing months, and paging with the real least-privilege loan_app; the owner only creates dedicated fixtures. */
@Tag("db")
@org.springframework.test.context.ActiveProfiles("test")
@SpringBootTest(properties={"spring.datasource.username=loan_app", "spring.datasource.password=${LOAN_DW_APP_PASSWORD}"})
@AutoConfigureMockMvc
@Transactional
class CandidateWebTest {
    @Autowired MockMvc mvc;
    @Autowired ReviewRepository repo;
    @Autowired ReviewService service;
    @Autowired javax.sql.DataSource dataSource;
    final List<Long> ids = new ArrayList<>();
    String delivery;
    String prefix;
    long evidenceId;

    Connection ownerConnection() throws Exception {
        var c = DriverManager.getConnection("jdbc:oracle:thin:@//" + System.getenv().getOrDefault("LOAN_DW_DB_DSN", "localhost:1522/FREEPDB1"), "loan_oltp",
            System.getenv("LOAN_DW_OLTP_PASSWORD"));
        TestDatabaseGuard.check(c);
        c.setAutoCommit(false);
        return c;
    }

    @BeforeEach
    void fixtures() throws Exception {
        delivery = UUID.randomUUID().toString().replace("-", "");
        prefix = "T" + delivery.substring(0, 7);
        try (var c = ownerConnection()) {
            var j = JdbcClient.create(new SingleConnectionDataSource(c, true));
            j.sql("""
                insert into review_candidate_delivery (delivery_id, manifest_sha256, manifest_json, status)
                values (hextoraw(:d), :sha, '{}', 'PUBLISHED')
                """).param("d", delivery).param("sha", "a".repeat(64)).update();
            for (int i=0; i<105; i++) {
                long id = CandidateFixtures.insert(j, prefix + String.format("%04d", i));
                ids.add(id);
                j.sql("update review_candidate set candidate_source='SPARK' where candidate_id=:id")
                    .param("id", id).update();
            }
            evidenceId = addEvidence(j, ids.get(0), "a");
            c.commit();
        }
    }

    long addEvidence(JdbcClient j, long id, String hash) {
        j.sql("""
            insert into review_evidence (candidate_id, delivery_id, rule_version_id, data_source,
                loan_identifier, reporting_month, source_release_id, rule_code, version_no,
                min_delinquency_status, property_state, content_sha256, current_loan_delinquency_status,
                origination_year, first_payment_date, original_upb)
            select candidate_id, hextoraw(:d), rule_version_id, data_source, loan_identifier,
                reporting_month, source_release_id, 'DLQ60_ENTRY', 1, 2, :state, :sha, '02',
                2010, date '2010-01-01', 1000
            from review_candidate where candidate_id=:id
            """).param("d", delivery).param("state", hash.equals("a") ? "CA" : "NY")
            .param("sha", hash.repeat(64)).param("id", id).update();
        long eid = j.sql("select evidence_id from review_evidence where candidate_id=:id and content_sha256=:sha")
            .param("id", id).param("sha", hash.repeat(64)).query(Long.class).single();
        j.sql("insert into review_evidence_month (evidence_id, monthly_reporting_period, current_loan_delinquency_status) values (:e, date '2020-06-01', '02')")
            .param("e", eid).update();
        j.sql("update review_candidate set latest_evidence_id=:e where candidate_id=:id")
            .param("e", eid).param("id", id).update();
        return eid;
    }

    @AfterTransaction
    void clean() throws Exception {
        try (var c = ownerConnection()) {
            var j = JdbcClient.create(new SingleConnectionDataSource(c, true));
            for (Long id : ids) {
                j.sql("update review_candidate set latest_evidence_id=null where candidate_id=:id").param("id", id).update();
                j.sql("delete from review_evidence_month where evidence_id in (select evidence_id from review_evidence where candidate_id=:id)").param("id", id).update();
                j.sql("delete from review_evidence where candidate_id=:id").param("id", id).update();
                j.sql("delete from review_candidate where candidate_id=:id").param("id", id).update();
            }
            j.sql("delete from review_candidate_delivery where delivery_id=hextoraw(:d)").param("d", delivery).update();
            c.commit();
        }
    }

    @Test
    void frozenEvidenceAndNewVersionNotice() throws Exception {
        mvc.perform(get("/candidates/{id}", ids.get(0)).with(user("manager_demo").roles("MANAGER")))
            .andExpect(status().isOk()).andExpect(content().string(containsString("CA")))
            .andExpect(content().string(containsString("missing")));
        long caseId = service.openCase(ids.get(0), "manager_demo");
        assertThat(repo.caseEvidence(caseId).evidenceId()).isEqualTo(evidenceId);
        try (var c = ownerConnection()) {
            addEvidence(JdbcClient.create(new SingleConnectionDataSource(c, true)), ids.get(0), "b");
            c.commit();
        }
        assertThat(repo.caseEvidence(caseId).evidenceId()).isEqualTo(evidenceId);
        assertThat(repo.loanInfo(evidenceId).orElseThrow().propertyState()).isEqualTo("CA");
        assertThat(repo.recentMonths(evidenceId, LocalDate.of(2020,6,1))).hasSize(13)
            .filteredOn(ReviewRepository.MonthRow::missing).hasSize(12);
        mvc.perform(get("/cases/{id}", caseId).with(user("manager_demo").roles("MANAGER")))
            .andExpect(status().isOk()).andExpect(content().string(containsString("Newer evidence exists")))
            .andExpect(content().string(containsString("CA")));
    }

    @Test
    void monthFilterAndBusinessKeyPagination() throws Exception {
        mvc.perform(get("/candidates").param("loan", prefix + "0000").with(user("manager_demo").roles("MANAGER")))
            .andExpect(status().isOk()).andExpect(org.springframework.test.web.servlet.result.MockMvcResultMatchers.model()
                .attribute("candidates", org.hamcrest.Matchers.hasSize(1)));
        mvc.perform(get("/candidates").param("loan", "' or '1'='1").with(user("manager_demo").roles("MANAGER")))
            .andExpect(status().isOk()).andExpect(org.springframework.test.web.servlet.result.MockMvcResultMatchers.model()
                .attribute("candidates", org.hamcrest.Matchers.empty()));
        var all = new ArrayList<Long>();
        String after = null;
        do {
            var page = repo.candidates(null, LocalDate.of(2020,6,1), 50, after);
            var visible = page.subList(0, Math.min(50, page.size()));
            all.addAll(visible.stream().map(ReviewRepository.CandidateRow::candidateId).toList());
            after = page.size() > 50 ? repo.candidateCursor(visible.get(visible.size()-1).candidateId()) : null;
        } while (after != null);
        assertThat(all).doesNotHaveDuplicates().containsAll(ids);
        assertThat(repo.candidates(prefix + "0000", LocalDate.of(2020,7,1),50,null)).isEmpty();
        mvc.perform(get("/candidates").param("month", "2099-12").with(user("manager_demo").roles("MANAGER")))
            .andExpect(status().isOk()).andExpect(content().string(containsString("No candidates")));
        mvc.perform(get("/candidates").param("month", "bad").with(user("manager_demo").roles("MANAGER")))
            .andExpect(status().isBadRequest());
        mvc.perform(get("/candidates").param("after", "bad~FRE~x~1").with(user("manager_demo").roles("MANAGER")))
            .andExpect(status().isBadRequest());
        for (String size : List.of("0", "101")) {
            mvc.perform(get("/candidates").param("size",size).with(user("manager_demo").roles("MANAGER")))
                .andExpect(status().isBadRequest());
        }
    }
}
