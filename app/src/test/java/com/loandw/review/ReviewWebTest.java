package com.loandw.review;

import static org.assertj.core.api.Assertions.assertThat;
import static org.hamcrest.Matchers.containsString;
import static org.hamcrest.Matchers.empty;
import static org.hamcrest.Matchers.hasSize;
import static org.hamcrest.Matchers.not;
import static org.springframework.security.test.web.servlet.request.SecurityMockMvcRequestBuilders.formLogin;
import static org.springframework.security.test.web.servlet.request.SecurityMockMvcRequestPostProcessors.csrf;
import static org.springframework.security.test.web.servlet.request.SecurityMockMvcRequestPostProcessors.user;
import static org.springframework.security.test.web.servlet.response.SecurityMockMvcResultMatchers.authenticated;
import static org.springframework.security.test.web.servlet.response.SecurityMockMvcResultMatchers.unauthenticated;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.get;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.post;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.content;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.flash;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.header;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.model;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.redirectedUrl;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

import java.util.List;

import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Tag;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.boot.webmvc.test.autoconfigure.AutoConfigureMockMvc;
import org.springframework.jdbc.core.simple.JdbcClient;
import org.springframework.security.crypto.password.PasswordEncoder;
import org.springframework.test.web.servlet.MockMvc;
import org.springframework.test.web.servlet.request.RequestPostProcessor;
import org.springframework.transaction.annotation.Transactional;

import com.loandw.review.repository.ReviewRepository.CaseRow;
import com.loandw.review.repository.ReviewRepository.ReportTotal;
import com.loandw.review.service.ReviewService;

/**
 * Automated tests of the web application: one test per security requirement, plus a full workflow.
 * Connects to real Oracle (OLTP tables, triggers, review_api are all real); each test runs in one transaction that is fully rolled back, leaving no test data.
 * Test data: a dedicated TEST candidate referencing a sample loan, to verify the CDC flow back; the candidate reference procedure is not called.
 * Run: scripts/12_run_app.sh test
 */
@Tag("db")
@org.springframework.test.context.ActiveProfiles("test")
@SpringBootTest
@AutoConfigureMockMvc
@Transactional
class ReviewWebTest {

    private static final String ANALYST = "analyst_demo";
    private static final String MANAGER = "manager_demo";

    @Autowired
    private MockMvc mvc;
    @Autowired
    private JdbcClient jdbc;
    @Autowired
    private ReviewService service;
    @Autowired
    private PasswordEncoder encoder;

    /** A candidate without a case yet. */
    private long candidateId;
    private String candidateLoan;

    private final java.util.List<Long> fixtureIds = new java.util.ArrayList<>();
    private java.sql.Connection ownerConnection() throws java.sql.SQLException {
        var c = java.sql.DriverManager.getConnection("jdbc:oracle:thin:@//" + System.getenv().getOrDefault("LOAN_DW_DB_DSN", "localhost:1522/FREEPDB1"),
            "loan_oltp", System.getenv("LOAN_DW_OLTP_PASSWORD"));
        TestDatabaseGuard.check(c);
        c.setAutoCommit(false);
        return c;
    }

    @org.springframework.test.context.transaction.AfterTransaction
    void cleanFixtures() throws Exception {
        if (fixtureIds.isEmpty()) return;
        try (var c = ownerConnection()) {
            var owner = JdbcClient.create(new org.springframework.jdbc.datasource.SingleConnectionDataSource(c, true));
            for (Long id : fixtureIds) owner.sql("delete from review_candidate where candidate_source='TEST' and candidate_id=:id")
                .param("id", id).update();
            fixtureIds.clear();
            c.commit();
        }
    }

    @BeforeEach
    void makeCandidates() {
        var loans = jdbc.sql("""
            select d.loan_identifier from loan_dw.dim_loan d where d.release_id='R47'
                and not exists (select 1 from review_candidate c where c.loan_identifier=d.loan_identifier)
            order by d.loan_identifier fetch first 5 rows only
            """).query(String.class).list();
        try (var connection = ownerConnection()) {
            var owner = JdbcClient.create(new org.springframework.jdbc.datasource.SingleConnectionDataSource(connection, true));
            for (String loan : loans) fixtureIds.add(CandidateFixtures.insert(owner, loan));
            connection.commit();
            candidateId = fixtureIds.get(0);
        } catch (java.sql.SQLException e) { throw new IllegalStateException(e); }
        candidateLoan = jdbc.sql("select loan_identifier from review_candidate where candidate_id = :id")
            .param("id", candidateId)
            .query(String.class)
            .single();
    }

    // ---------- Security requirements, one by one ----------

    @Test
    @DisplayName("SQL injection: quotes and or in the input are only text to search for, never SQL")
    void sqlInjectionIsTreatedAsText() throws Exception {
        // TEST-source candidates are not shown on the delivered candidate page; SPARK loan search and the injection counterexample are in CandidateWebTest.
        mvc.perform(get("/candidates").param("loan", candidateLoan).with(as(ANALYST)))
            .andExpect(status().isOk())
            .andExpect(model().attribute("candidates", empty()));
        // Classic injection: concatenated into SQL the condition would always be true and return every candidate; with bound parameters it is just a loan ID that does not exist
        mvc.perform(get("/candidates").param("loan", "' or '1'='1").with(as(ANALYST)))
            .andExpect(status().isOk())
            .andExpect(model().attribute("candidates", empty()));
        // Write inputs too: SQL stuffed into the release is stopped by format validation, and no database row changes
        long before = count("select count(*) from review_candidate");
        mvc.perform(post("/candidates/generate").with(as(MANAGER)).with(csrf())
                .param("releaseId", "R47' or 1=1 --").param("month", "2020-07").param("ruleCode", "DLQ60_ENTRY"))
            .andExpect(status().isForbidden());
        assertThat(count("select count(*) from review_candidate")).isEqualTo(before);
    }

    @Test
    @DisplayName("An unassigned case waits for a manager to assign it; the page shows no note form, and a direct submission is refused")
    void openCaseDoesNotOfferAnnotation() throws Exception {
        long caseId = openCase(ANALYST);
        mvc.perform(get("/cases/{id}", caseId).with(as(ANALYST)))
            .andExpect(status().isOk())
            .andExpect(content().string(containsString("after a manager assigns")))
            .andExpect(content().string(not(containsString("/cases/" + caseId + "/annotate"))));
        mvc.perform(post("/cases/{id}/annotate", caseId).with(as(ANALYST)).with(csrf())
                .param("noteText", "submitted directly, bypassing the page"))
            .andExpect(flash().attribute("error", containsString("not assigned yet")));
        assertThat(count("select count(*) from case_annotation where case_id = " + caseId)).isZero();
    }

    @Test
    @DisplayName("XSS: a <script> in a note is stored as is, escaped to text on the page, and the CSP header is present")
    void scriptInNoteIsEscaped() throws Exception {
        long caseId = caseInReview();
        String attack = "<script>alert('xss')</script>";
        mvc.perform(post("/cases/{id}/annotate", caseId).with(as(ANALYST)).with(csrf()).param("noteText", attack))
            .andExpect(redirectedUrl("/cases/" + caseId));
        // The database stores exactly what the user wrote (nothing is rewritten on input; escaping happens on output)
        assertThat(jdbc.sql("select note_text from case_annotation where case_id = :id and note_text = :note")
            .param("id", caseId).param("note", attack).query(String.class).single()).isEqualTo(attack);
        mvc.perform(get("/cases/{id}", caseId).with(as(ANALYST)))
            .andExpect(status().isOk())
            .andExpect(content().string(containsString("&lt;script&gt;alert(&#39;xss&#39;)&lt;/script&gt;")))
            .andExpect(content().string(not(containsString(attack))))
            .andExpect(header().string("Content-Security-Policy", containsString("script-src 'self'")));
    }

    @Test
    @DisplayName("Critical operations need confirmation: closing without ticking \"I confirm\" does nothing; with it the case closes")
    void decisionNeedsConfirmation() throws Exception {
        long caseId = caseInReview();
        mvc.perform(post("/cases/{id}/decide", caseId).with(as(MANAGER)).with(csrf())
                .param("expectedStatus", caseStatus(caseId)).param("decisionType", "CLOSE").param("decisionNote", "review complete"))
            .andExpect(status().isOk())
            .andExpect(model().attributeHasFieldErrors("decisionForm", "confirmed"));
        assertThat(caseStatus(caseId)).isEqualTo("IN_REVIEW");
        assertThat(count("select count(*) from review_decision where case_id = " + caseId)).isZero();

        mvc.perform(post("/cases/{id}/decide", caseId).with(as(MANAGER)).with(csrf())
                .param("expectedStatus", caseStatus(caseId)).param("decisionType", "CLOSE").param("decisionNote", "review complete").param("confirmed", "true"))
            .andExpect(redirectedUrl("/cases/" + caseId))
            .andExpect(flash().attribute("message", "Case closed"));
        assertThat(caseStatus(caseId)).isEqualTo("CLOSED");
    }

    @Test
    @DisplayName("Reopen: analysts cannot; managers must confirm, and the case returns to review")
    void reopenNeedsManagerAndConfirmation() throws Exception {
        long caseId = caseInReview();
        decide(caseId, "CLOSE");
        assertThat(caseStatus(caseId)).isEqualTo("CLOSED");

        mvc.perform(post("/cases/{id}/decide", caseId).with(as(ANALYST)).with(csrf())
                .param("expectedStatus", caseStatus(caseId)).param("decisionType", "REOPEN").param("decisionNote", "not allowed").param("confirmed", "true"))
            .andExpect(status().isForbidden());
        mvc.perform(post("/cases/{id}/decide", caseId).with(as(MANAGER)).with(csrf())
                .param("expectedStatus", caseStatus(caseId)).param("decisionType", "REOPEN").param("decisionNote", "review new information"))
            .andExpect(model().attributeHasFieldErrors("decisionForm", "confirmed"));
        assertThat(caseStatus(caseId)).isEqualTo("CLOSED");
        assertThat(count("select count(*) from review_decision where case_id = " + caseId)).isEqualTo(1);

        mvc.perform(get("/cases/{id}", caseId).with(as(MANAGER)))
            .andExpect(content().string(containsString("value=\"REOPEN\"")));
        mvc.perform(post("/cases/{id}/decide", caseId).with(as(MANAGER)).with(csrf())
                .param("expectedStatus", caseStatus(caseId)).param("decisionType", "REOPEN").param("decisionNote", "review new information").param("confirmed", "true"))
            .andExpect(flash().attribute("message", "Case reopened"));
        assertThat(caseStatus(caseId)).isEqualTo("IN_REVIEW");
        assertThat(count("select count(*) from risk_review_case where case_id = " + caseId
            + " and closed_at is null")).isEqualTo(1);
    }

    @Test
    @DisplayName("Input validation: empty note, overlong note, unknown decision type, invalid analyst ID and month are all stopped")
    void invalidInputIsRejected() throws Exception {
        long caseId = caseInReview();
        mvc.perform(post("/cases/{id}/annotate", caseId).with(as(ANALYST)).with(csrf()).param("noteText", "   "))
            .andExpect(model().attributeHasFieldErrors("noteForm", "noteText"));
        mvc.perform(post("/cases/{id}/annotate", caseId).with(as(ANALYST)).with(csrf())
                .param("noteText", "é".repeat(1001)))
            .andExpect(model().attributeHasFieldErrors("noteForm", "noteText"));
        mvc.perform(post("/cases/{id}/decide", caseId).with(as(MANAGER)).with(csrf())
                .param("expectedStatus", caseStatus(caseId)).param("decisionType", "DELETE").param("decisionNote", "x").param("confirmed", "true"))
            .andExpect(model().attributeHasFieldErrors("decisionForm", "decisionType"));
        mvc.perform(post("/cases/{id}/assign", caseId).with(as(MANAGER)).with(csrf()).param("assigneeUserId", "-1"))
            .andExpect(model().attributeHasFieldErrors("assignForm", "assigneeUserId"));
        mvc.perform(post("/candidates/generate").with(as(MANAGER)).with(csrf())
                .param("releaseId", "R47").param("month", "2020-13").param("ruleCode", "DLQ60_ENTRY"))
            .andExpect(status().isForbidden());
        // Nothing was written to the database: only the one note written by caseInReview()
        assertThat(count("select count(*) from case_annotation where case_id = " + caseId)).isEqualTo(1);
        assertThat(caseStatus(caseId)).isEqualTo("IN_REVIEW");
    }

    @Test
    @DisplayName("Passwords: the database stores only BCrypt hashes; login compares hashes and succeeds only with the right password")
    void passwordsAreBcrypt() throws Exception {
        // Users with a password all store BCrypt hashes (starting with $2a$ / $2b$ / $2y$, 60 characters), not plain text
        assertThat(jdbc.sql("""
                select count(*) from app_user
                where password_hash is not null
                   and not regexp_like(password_hash, '^\\$2[aby]\\$[0-9]{2}\\$.{53}$')
                """).query(Integer.class).single()).isZero();
        // Temporarily set a known password in the test (rolled back at the end, the passwords in app/demo-users.local.txt are unaffected)
        jdbc.sql("update app_user set password_hash = :h where username = :u")
            .param("h", encoder.encode("only-for-this-test-1"))
            .param("u", ANALYST)
            .update();
        mvc.perform(formLogin("/login").user(ANALYST).password("only-for-this-test-1"))
            .andExpect(authenticated().withUsername(ANALYST).withRoles("ANALYST"))
            .andExpect(redirectedUrl("/"));
        mvc.perform(formLogin("/login").user(ANALYST).password("wrong-password"))
            .andExpect(unauthenticated())
            .andExpect(redirectedUrl("/login?error"));
    }

    @Test
    @DisplayName("No business role: cannot log in even with an active account and the right password")
    void activeUserWithoutRoleCannotLogin() throws Exception {
        String username = "no_role_test";
        String password = "only-for-this-test-2";
        jdbc.sql("insert into app_user (username, full_name, password_hash) values (:u, :n, :h)")
            .param("u", username)
            .param("n", "user without role")
            .param("h", encoder.encode(password))
            .update();

        mvc.perform(formLogin("/login").user(username).password(password))
            .andExpect(unauthenticated())
            .andExpect(redirectedUrl("/login?error"));
    }

    @Test
    @DisplayName("Role-based authorization: an analyst calling manager functions gets 403 and cannot see other people's cases")
    void analystCannotUseManagerActions() throws Exception {
        long caseId = openCase(ANALYST);
        long analystId = userId(ANALYST);
        mvc.perform(post("/candidates/generate").with(as(ANALYST)).with(csrf())
                .param("releaseId", "R47").param("month", "2020-07").param("ruleCode", "DLQ60_ENTRY"))
            .andExpect(status().isForbidden());
        mvc.perform(post("/cases/{id}/assign", caseId).with(as(ANALYST)).with(csrf())
                .param("assigneeUserId", String.valueOf(analystId)))
            .andExpect(status().isForbidden());
        mvc.perform(post("/cases/{id}/decide", caseId).with(as(ANALYST)).with(csrf())
                .param("expectedStatus", caseStatus(caseId)).param("decisionType", "CLOSE").param("decisionNote", "x").param("confirmed", "true"))
            .andExpect(status().isForbidden());
        assertThat(count("select count(*) from case_assignment where case_id = " + caseId)).isZero();
        assertThat(count("select count(*) from review_decision where case_id = " + caseId)).isZero();

        // A case opened by the manager and not assigned to this analyst: editing the URL neither shows it nor allows a note
        long managersCase = service.openCase(nextCandidate(), MANAGER);
        mvc.perform(get("/cases/{id}", managersCase).with(as(ANALYST)))
            .andExpect(status().isForbidden());
        mvc.perform(post("/cases/{id}/annotate", managersCase).with(as(ANALYST)).with(csrf()).param("noteText", "x"))
            .andExpect(status().isForbidden());
        assertThat(count("select count(*) from case_annotation where case_id = " + managersCase)).isZero();
    }

    @Test
    @DisplayName("CSRF: a submission without a token gets 403 and nothing runs")
    void postWithoutCsrfIsRejected() throws Exception {
        long caseId = openCase(ANALYST);
        mvc.perform(post("/cases/{id}/annotate", caseId).with(as(ANALYST)).param("noteText", "submission forged by another site"))
            .andExpect(status().isForbidden());
        assertThat(count("select count(*) from case_annotation where case_id = " + caseId)).isZero();
        mvc.perform(post("/candidates/{id}/open", nextCandidate()).with(as(ANALYST)))
            .andExpect(status().isForbidden());
    }

    @Test
    @DisplayName("Not logged in: every page redirects to the login page")
    void anonymousIsSentToLogin() throws Exception {
        mvc.perform(get("/cases"))
            .andExpect(status().is3xxRedirection())
            .andExpect(redirectedUrl("/login"));
    }

    @Test
    @DisplayName("Missing case: viewing returns 404, actions show a readable reason, not 500")
    void missingCaseIsHandled() throws Exception {
        long missing = 999_999_999L;
        mvc.perform(get("/cases/{id}", missing).with(as(MANAGER)))
            .andExpect(status().isNotFound());
        mvc.perform(post("/cases/{id}/annotate", missing).with(as(MANAGER)).with(csrf()).param("noteText", "x"))
            .andExpect(flash().attribute("error", containsString("not found")));
        mvc.perform(post("/cases/{id}/decide", missing).with(as(MANAGER)).with(csrf())
                .param("expectedStatus", "IN_REVIEW").param("decisionType", "CLOSE").param("decisionNote", "x").param("confirmed", "true"))
            .andExpect(flash().attribute("error", containsString("not found")));
    }

    // ---------- Full workflow ----------

    @Test
    @DisplayName("Full workflow: candidate -> open -> assign -> note -> escalate -> close -> visible in the report; operations the database rejects show a readable reason")
    void fullWorkflow() throws Exception {
        mvc.perform(post("/candidates/generate").with(as(MANAGER)).with(csrf())
                .param("releaseId", "R47").param("month", "2020-07").param("ruleCode", "DLQ60_ENTRY"))
            .andExpect(status().isForbidden());

        long caseId = openCase(ANALYST);
        // Opening the same candidate again: the unique constraint rejects it and the reason is shown
        mvc.perform(post("/candidates/{id}/open", candidateId).with(as(ANALYST)).with(csrf()))
            .andExpect(flash().attribute("error", containsString("already has a case")));
        // Assigning to a manager is refused (only analysts can be assigned) and the reason is shown
        mvc.perform(post("/cases/{id}/assign", caseId).with(as(MANAGER)).with(csrf())
                .param("assigneeUserId", String.valueOf(userId(MANAGER))))
            .andExpect(flash().attribute("error", "Cases can only be assigned to analysts"));
        assertThat(caseStatus(caseId)).isEqualTo("OPEN");

        mvc.perform(post("/cases/{id}/assign", caseId).with(as(MANAGER)).with(csrf())
                .param("assigneeUserId", String.valueOf(userId(ANALYST))))
            .andExpect(flash().attribute("message", "Case assigned"));
        assertThat(caseStatus(caseId)).isEqualTo("ASSIGNED");
        mvc.perform(post("/cases/{id}/annotate", caseId).with(as(ANALYST)).with(csrf()).param("noteText", "first 60+ in 12 months"))
            .andExpect(flash().attribute("message", "Note saved"));
        assertThat(caseStatus(caseId)).isEqualTo("IN_REVIEW");
        decide(caseId, "ESCALATE");
        assertThat(caseStatus(caseId)).isEqualTo("ESCALATED");
        decide(caseId, "CLOSE");
        assertThat(caseStatus(caseId)).isEqualTo("CLOSED");

        // A note after closing is refused
        mvc.perform(post("/cases/{id}/annotate", caseId).with(as(ANALYST)).with(csrf()).param("noteText", "addendum"))
            .andExpect(flash().attribute("error", containsString("The case is closed")));
        // The analyst's case list contains it; the detail page shows the history
        List<?> cases = (List<?>) mvc.perform(get("/cases").with(as(ANALYST)))
            .andReturn().getModelAndView().getModel().get("cases");
        assertThat(cases).anyMatch(row -> ((CaseRow) row).caseId() == caseId);
        mvc.perform(get("/cases/{id}", caseId).with(as(ANALYST)))
            .andExpect(status().isOk())
            .andExpect(model().attribute("activities", hasSize(9)));

        // Visible in the report: after the incremental extraction into the warehouse and the report recomputation, the monthly report page shows this closed case
        jdbc.sql("begin loan_dw.cdc_review(10); loan_dw.load_ads_review_case_monthly; end;").update();
        ReportTotal total = (ReportTotal) mvc.perform(get("/reports").with(as(ANALYST)))
            .andExpect(status().isOk())
            .andReturn().getModelAndView().getModel().get("total");
        assertThat(total.caseCount()).isEqualTo(count("select count(*) from risk_review_case"));
        assertThat(total.closedCount()).isGreaterThanOrEqualTo(1);
        assertThat(total.escalatedCount()).isGreaterThanOrEqualTo(1);
        assertThat(total.dataUntil()).isNotNull();
    }

    @Test
    @DisplayName("Escalate and close from the same stale page succeed only once; the second is refused in either order")
    void staleDecisionIsRejectedInBothOrders() throws Exception {
        for (String first : List.of("ESCALATE", "CLOSE")) {
            long id = service.openCase(nextCandidate(), ANALYST);
            service.assignCase(id, userId(ANALYST), MANAGER);
            service.addAnnotation(id, ANALYST, "review");
            String second = first.equals("CLOSE") ? "ESCALATE" : "CLOSE";
            mvc.perform(post("/cases/{id}/decide", id).with(as(MANAGER)).with(csrf())
                    .param("decisionType", first).param("decisionNote", "first")
                    .param("expectedStatus", "IN_REVIEW").param("confirmed", "true"))
                .andExpect(flash().attributeExists("message"));
            mvc.perform(post("/cases/{id}/decide", id).with(as(MANAGER)).with(csrf())
                    .param("decisionType", second).param("decisionNote", "second")
                    .param("expectedStatus", "IN_REVIEW").param("confirmed", "true"))
                .andExpect(flash().attribute("error", containsString("Please refresh")));
            assertThat(count("select count(*) from review_decision where case_id = " + id)).isEqualTo(1);
            assertThat(count("select count(*) from case_status_history where case_id = " + id)).isEqualTo(4);
        }
    }

    @Test
    void decisionWithoutPageStateIsRejected() throws Exception {
        long id = caseInReview();
        mvc.perform(post("/cases/{id}/decide", id).with(as(MANAGER)).with(csrf())
                .param("decisionType", "CLOSE").param("decisionNote", "page state missing").param("confirmed", "true"))
            .andExpect(model().attributeHasFieldErrors("decisionForm", "expectedStatus"));
        assertThat(caseStatus(id)).isEqualTo("IN_REVIEW");
        assertThat(count("select count(*) from review_decision where case_id = " + id)).isZero();
    }

    @Test
    @DisplayName("English interface: with or without ?lang=en, pages, success messages, business rejections, and form validation are in English")
    void englishInterface() throws Exception {
        long id = caseInReview();
        mvc.perform(post("/cases/{id}/decide", id).with(as(MANAGER)).with(csrf()).param("lang", "en")
                .param("expectedStatus", "IN_REVIEW").param("decisionType", "CLOSE"))
            .andExpect(content().string(containsString("Tick &quot;I confirm&quot;")));
        mvc.perform(post("/cases/{id}/decide", id).with(as(MANAGER)).with(csrf()).param("lang", "en")
                .param("expectedStatus", "IN_REVIEW").param("decisionType", "CLOSE")
                .param("decisionNote", "English reason").param("confirmed", "true"))
            .andExpect(flash().attribute("message", "Case closed"));
        mvc.perform(post("/cases/{id}/annotate", id).with(as(MANAGER)).with(csrf()).param("lang", "en")
                .param("noteText", "after close"))
            .andExpect(flash().attribute("error", "The case is closed and cannot be changed: " + id));

        // User names and notes written by tests are data, not interface text; remove them before checking for CJK characters
        List<String> data = jdbc.sql("select full_name from app_user").query(String.class).list();
        for (String url : List.of("/", "/candidates", "/cases", "/cases/" + id,
                "/reports", "/account/password")) {
            String page = mvc.perform(get(url).param("lang", "en").with(as(MANAGER)))
                .andExpect(status().isOk())
                .andReturn().getResponse().getContentAsString(java.nio.charset.StandardCharsets.UTF_8);
            for (String d : data) page = page.replace(d, "");
            // HTML comments are for developers and not shown by the browser; remove them too
            page = page.replaceAll("(?s)<!--.*?-->", "").replace("test note", "").replace(">English<", "><");
            assertThat(page).as(url).doesNotContainPattern("[\\u3400-\\u9fff\\u3000-\\u303f\\uff00-\\uffef]");
        }
        mvc.perform(get("/cases/{id}", id).param("lang", "en").with(as(MANAGER)))
            .andExpect(content().string(containsString("Closed")))
            .andExpect(content().string(containsString("Close: English reason")))
            .andExpect(content().string(containsString("(opened) → Open")));
        mvc.perform(get("/cases/{id}", id).with(as(MANAGER)))
            .andExpect(content().string(containsString("Closed")))
            .andExpect(content().string(containsString("Close: English reason")));
    }

    // ---------- Helpers ----------

    private static RequestPostProcessor as(String username) {
        return user(username).roles(ANALYST.equals(username) ? "ANALYST" : "MANAGER");
    }

    /** Open a case through the web page and return the case ID (taken from the redirect /cases/{id}). */
    private long openCase(String username) throws Exception {
        String url = mvc.perform(post("/candidates/{id}/open", candidateId).with(as(username)).with(csrf()))
            .andExpect(status().is3xxRedirection())
            .andReturn().getResponse().getRedirectedUrl();
        assertThat(url).startsWith("/cases/");
        return Long.parseLong(url.substring("/cases/".length()));
    }

    /** Analyst opens -> manager assigns to the analyst -> analyst writes a note: the case enters "In review". */
    private long caseInReview() throws Exception {
        long caseId = openCase(ANALYST);
        service.assignCase(caseId, userId(ANALYST), MANAGER);
        service.addAnnotation(caseId, ANALYST, "test note");
        assertThat(caseStatus(caseId)).isEqualTo("IN_REVIEW");
        return caseId;
    }

    private void decide(long caseId, String type) throws Exception {
        mvc.perform(post("/cases/{id}/decide", caseId).with(as(MANAGER)).with(csrf())
                .param("expectedStatus", caseStatus(caseId)).param("decisionType", type).param("decisionNote", "test").param("confirmed", "true"))
            .andExpect(redirectedUrl("/cases/" + caseId))
            .andExpect(flash().attributeCount(1))
            .andExpect(flash().attributeExists("message"));
    }

    /** Another candidate without a case yet. */
    private long nextCandidate() {
        return fixtureIds.stream().filter(id -> jdbc.sql("select count(*) from risk_review_case where candidate_id=:id")
            .param("id", id).query(Integer.class).single() == 0).findFirst().orElseThrow();
    }

    private String caseStatus(long caseId) {
        return jdbc.sql("select current_status from risk_review_case where case_id = :id")
            .param("id", caseId)
            .query(String.class)
            .single();
    }

    private long userId(String username) {
        return jdbc.sql("select user_id from app_user where username = :u").param("u", username)
            .query(Long.class).single();
    }

    /** Count SQL written by the test itself (it concatenates only the test's own numbers, never user input). */
    private long count(String sql) {
        return jdbc.sql(sql).query(Long.class).single();
    }
}
