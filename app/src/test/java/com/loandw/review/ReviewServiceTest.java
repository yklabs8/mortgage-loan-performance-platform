package com.loandw.review;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;

import java.util.concurrent.Executors;
import java.util.concurrent.TimeUnit;
import java.util.concurrent.TimeoutException;
import javax.sql.DataSource;

import org.junit.jupiter.api.Tag;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.Timeout;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.boot.webmvc.test.autoconfigure.AutoConfigureMockMvc;
import org.springframework.jdbc.core.simple.JdbcClient;
import org.springframework.test.web.servlet.MockMvc;
import org.springframework.transaction.PlatformTransactionManager;
import org.springframework.transaction.annotation.Propagation;
import org.springframework.transaction.annotation.Transactional;
import org.springframework.transaction.support.TransactionTemplate;

import com.loandw.review.repository.ReviewApiException;
import com.loandw.review.service.ReviewService;

/** Real Oracle: the owner revokes roles in the same transaction and builds concurrency fixtures; ordinary tests roll back, concurrency fixtures are cleaned by ID at the end. The restricted web account is verified separately by ReviewWebTest. */
@Tag("db")
@org.springframework.test.context.ActiveProfiles("test")
@SpringBootTest(properties = {"spring.datasource.username=loan_oltp",
    "spring.datasource.password=${LOAN_DW_OLTP_PASSWORD}"})
@AutoConfigureMockMvc
@Transactional
class ReviewServiceTest {
    @Autowired private ReviewService service;
    @Autowired private JdbcClient jdbc;
    @Autowired private DataSource dataSource;
    @Autowired private PlatformTransactionManager transactionManager;
    @Autowired private MockMvc mvc;
    @org.springframework.test.context.bean.override.mockito.MockitoSpyBean
    private com.loandw.review.repository.ReviewRepository repository;

    private long userId(String username) {
        return jdbc.sql("select user_id from app_user where username = :u").param("u", username)
            .query(Long.class).single();
    }

    private long open() {
        long candidate = CandidateFixtures.insert(jdbc, "T" + java.util.UUID.randomUUID().toString().replace("-", "").substring(0, 11));
        return service.openCase(candidate, "analyst_demo");
    }

    @Test
    void sampleCandidatesAreHidden() {
        long id = open();
        long candidate = jdbc.sql("select candidate_id from risk_review_case where case_id=:id")
            .param("id", id).query(Long.class).single();
        String loan = jdbc.sql("select loan_identifier from review_candidate where candidate_id=:id")
            .param("id", candidate).query(String.class).single();
        assertThat(repository.candidates(loan)).isEmpty();
    }

    private String state(long id) {
        return jdbc.sql("select current_status from risk_review_case where case_id = :id")
            .param("id", id).query(String.class).single();
    }

    private void decide(long id, String user, String type) {
        service.decideCase(id, user, type, "test decision", state(id));
    }

    private long inReview() {
        long id = open();
        service.assignCase(id, userId("analyst_demo"), "manager_demo");
        service.addAnnotation(id, "analyst_demo", "test note");
        return id;
    }

    @Test
    void workflowAndReopen() {
        long id = inReview();
        decide(id, "manager_demo", "CLOSE");
        assertThat(state(id)).isEqualTo("CLOSED");
        var firstClosedAt = jdbc.sql("select closed_at from risk_review_case where case_id = :id")
            .param("id", id).query(java.time.LocalDateTime.class).single();
        assertThat(jdbc.sql("select count(*) from case_status_history where case_id = :id")
            .param("id", id).query(Integer.class).single()).isEqualTo(4);
        assertThatThrownBy(() -> decide(id, "analyst_demo", "REOPEN"))
            .isInstanceOf(ReviewApiException.class).hasMessage("error.decide.managerOnly");
        decide(id, "manager_demo", "REOPEN");
        assertThat(state(id)).isEqualTo("IN_REVIEW");
        assertThat(jdbc.sql("select count(*) from case_status_history where case_id = :id")
            .param("id", id).query(Integer.class).single()).isEqualTo(5);
        assertThat(jdbc.sql("select count(*) from risk_review_case where case_id = :id and closed_at is null")
            .param("id", id).query(Integer.class).single()).isEqualTo(1);
        assertThat(jdbc.sql("select count(*) from review_decision where case_id = :id and decided_as_role = 'MANAGER'")
            .param("id", id).query(Integer.class).single()).isEqualTo(2);
        assertThatThrownBy(() -> decide(id, "manager_demo", "REOPEN"))
            .isInstanceOf(ReviewApiException.class).hasMessage("error.decide.notAllowed");
        decide(id, "manager_demo", "CLOSE");
        assertThat(jdbc.sql("select closed_at from risk_review_case where case_id = :id")
            .param("id", id).query(java.time.LocalDateTime.class).single()).isAfter(firstClosedAt);
        assertThat(jdbc.sql("select count(*) from risk_review_case where case_id = :id and closed_at is not null")
            .param("id", id).query(Integer.class).single()).isEqualTo(1);
        assertThatThrownBy(() -> service.addAnnotation(id, "analyst_demo", "note after close"))
            .isInstanceOf(ReviewApiException.class).hasMessage("error.case.closed");
    }

    @Test
    void workflowRejections() {
        long id = open();
        assertThatThrownBy(() -> service.addAnnotation(id, "analyst_demo", "not assigned"))
            .isInstanceOf(ReviewApiException.class).hasMessage("error.note.notAssigned");
        assertThatThrownBy(() -> service.assignCase(id, userId("analyst_demo"), "analyst_demo"))
            .isInstanceOf(ReviewApiException.class).hasMessage("error.assign.managerOnly");
        assertThatThrownBy(() -> service.assignCase(id, userId("manager_demo"), "manager_demo"))
            .isInstanceOf(ReviewApiException.class).hasMessage("error.assign.analystOnly");
        service.assignCase(id, userId("analyst_demo"), "manager_demo");
        assertThatThrownBy(() -> decide(id, "analyst_demo", "CLOSE"))
            .isInstanceOf(ReviewApiException.class).hasMessage("error.decide.managerOnly");
        assertThatThrownBy(() -> decide(id, "manager_demo", "CLOSE"))
            .isInstanceOf(ReviewApiException.class).hasMessage("error.decide.notAllowed");
        service.addAnnotation(id, "analyst_demo", "note before escalation");
        decide(id, "manager_demo", "ESCALATE");
        assertThatThrownBy(() -> decide(id, "manager_demo", "ESCALATE"))
            .isInstanceOf(ReviewApiException.class).hasMessage("error.decide.notAllowed");
        long candidate = jdbc.sql("select candidate_id from risk_review_case where case_id = :id")
            .param("id", id).query(Long.class).single();
        assertThatThrownBy(() -> service.openCase(candidate, "analyst_demo"))
            .isInstanceOf(ReviewApiException.class).hasMessage("error.candidate.taken");
    }

    @Test
    void revokedManagerIsRejectedWithStaleLogin() throws Exception {
        long id = inReview();
        jdbc.sql("""
            delete from user_role where user_id = :id
               and role_id = (select role_id from app_role where role_code = 'MANAGER')
            """).param("id", userId("manager_demo")).update();
        mvc.perform(org.springframework.test.web.servlet.request.MockMvcRequestBuilders.post("/cases/{id}/decide", id)
                .with(org.springframework.security.test.web.servlet.request.SecurityMockMvcRequestPostProcessors.user("manager_demo").roles("MANAGER"))
                .with(org.springframework.security.test.web.servlet.request.SecurityMockMvcRequestPostProcessors.csrf())
                .param("decisionType", "CLOSE").param("decisionNote", "role revoked")
                .param("expectedStatus", "IN_REVIEW").param("confirmed", "true"))
            .andExpect(org.springframework.test.web.servlet.result.MockMvcResultMatchers.flash()
                .attribute("error", "Only managers can close, escalate or reopen a case"));
        assertThat(state(id)).isEqualTo("IN_REVIEW");
    }

    @Test
    void revokedManagerCannotSeeOthersCasesWithStaleLogin() throws Exception {
        long id = open();
        jdbc.sql("""
            delete from user_role where user_id = :id
               and role_id = (select role_id from app_role where role_code = 'MANAGER')
            """).param("id", userId("manager_demo")).update();
        var staleLogin = org.springframework.security.test.web.servlet.request.SecurityMockMvcRequestPostProcessors
            .user("manager_demo").roles("MANAGER");
        mvc.perform(org.springframework.test.web.servlet.request.MockMvcRequestBuilders.get("/cases/{id}", id).with(staleLogin))
            .andExpect(org.springframework.test.web.servlet.result.MockMvcResultMatchers.status().isForbidden());
        String list = mvc.perform(org.springframework.test.web.servlet.request.MockMvcRequestBuilders.get("/cases").with(staleLogin))
            .andExpect(org.springframework.test.web.servlet.result.MockMvcResultMatchers.status().isOk())
            .andReturn().getResponse().getContentAsString(java.nio.charset.StandardCharsets.UTF_8);
        assertThat(list).doesNotContain("/cases/" + id + "\"");
    }

    @Test
    void roleIsCheckedBeforeCaseState() {
        long id = inReview();
        decide(id, "manager_demo", "CLOSE");
        // Closed case, stale page state: the analyst must always get "no permission", not "closed" or "page expired".
        assertThatThrownBy(() -> service.assignCase(id, userId("analyst_demo"), "analyst_demo"))
            .isInstanceOf(ReviewApiException.class).hasMessage("error.assign.managerOnly");
        assertThatThrownBy(() -> service.decideCase(id, "analyst_demo", "REOPEN", "stale page", "IN_REVIEW"))
            .isInstanceOf(ReviewApiException.class).hasMessage("error.decide.managerOnly");
        assertThat(state(id)).isEqualTo("CLOSED");
    }

    @Test
    @Timeout(10)
    @Transactional(propagation = Propagation.NOT_SUPPORTED)
    void roleRejectionDoesNotWaitForCaseLock() throws Exception {
        long id = committedFixture();
        var executor = Executors.newSingleThreadExecutor();
        try (var lock = dataSource.getConnection()) {
            lock.setAutoCommit(false);
            try (var sql = lock.prepareStatement("select current_status from risk_review_case where case_id = ? for update")) {
                sql.setLong(1, id);
                sql.executeQuery().close();
            }
            java.util.List<java.util.concurrent.Callable<String>> attempts = java.util.List.of(
                () -> {
                    service.assignCase(id, userId("analyst_demo"), "analyst_demo");
                    return "SUCCESS";
                },
                () -> {
                    service.decideCase(id, "analyst_demo", "CLOSE", "no permission", "IN_REVIEW");
                    return "SUCCESS";
                });
            try {
                for (var call : attempts) {
                    var attempt = executor.submit(() -> new TransactionTemplate(transactionManager).execute(status -> {
                        try {
                            return call.call();
                        } catch (ReviewApiException e) {
                            return e.getMessage();
                        } catch (Exception e) {
                            throw new IllegalStateException(e);
                        } finally {
                            status.setRollbackOnly();
                        }
                    }));
                    try {
                        assertThat(attempt.get(1, TimeUnit.SECONDS)).endsWith(".managerOnly");
                    } catch (TimeoutException e) {
                        throw new AssertionError("An unauthorized request is waiting for the case lock", e);
                    }
                }
            } finally {
                lock.rollback();
            }
        } finally {
            executor.shutdownNow();
            try {
                assertThat(executor.awaitTermination(5, TimeUnit.SECONDS)).isTrue();
            } finally {
                removeFixture(id);
            }
        }
    }

    @Test
    @org.junit.jupiter.api.extension.ExtendWith(org.springframework.boot.test.system.OutputCaptureExtension.class)
    void writeOperationsAreLoggedWithoutNoteText(org.springframework.boot.test.system.CapturedOutput output) throws Exception {
        long candidate = CandidateFixtures.insert(jdbc, "L" + java.util.UUID.randomUUID().toString().replace("-", "").substring(0, 11));
        var analyst = org.springframework.security.test.web.servlet.request.SecurityMockMvcRequestPostProcessors
            .user("analyst_demo").roles("ANALYST");
        var csrf = org.springframework.security.test.web.servlet.request.SecurityMockMvcRequestPostProcessors.csrf();
        mvc.perform(org.springframework.test.web.servlet.request.MockMvcRequestBuilders.post("/candidates/{id}/open", candidate)
            .with(analyst).with(csrf));
        long id = jdbc.sql("select case_id from risk_review_case where candidate_id = :c").param("c", candidate)
            .query(Long.class).single();
        String secret = "note text never logged" + id;
        mvc.perform(org.springframework.test.web.servlet.request.MockMvcRequestBuilders.post("/cases/{id}/annotate", id)
            .with(analyst).with(csrf).param("noteText", secret));
        assertThat(output.getOut()).contains("action=OPEN user=analyst_demo candidate=" + candidate + " result=OK")
            .contains("action=NOTE user=analyst_demo case=" + id + " result=REJECTED code=error.note.notAssigned")
            .doesNotContain(secret);
    }

    @Test
    @Timeout(10)
    @Transactional(propagation = Propagation.NOT_SUPPORTED)
    void lockWaitIsBoundedAndDoesNotWrite() throws Exception {
        // The shared database currently has no committed cases. Only the dedicated fixture is committed; every business attempt rolls back, and finally cleans the fixture by ID.
        long assignments = jdbc.sql("select count(*) from case_assignment").query(Long.class).single();
        long id = committedFixture();
        var executor = Executors.newSingleThreadExecutor();
        try (var lock = dataSource.getConnection()) {
            lock.setAutoCommit(false);
            try (var sql = lock.prepareStatement("select current_status from risk_review_case where case_id = ? for update")) {
                sql.setLong(1, id);
                sql.executeQuery().close();
            }
            var attempt = executor.submit(() -> {
                var tx = new TransactionTemplate(transactionManager);
                return tx.execute(status -> {
                    try {
                        service.assignCase(id, userId("analyst_demo"), "manager_demo");
                        return "SUCCESS";
                    } catch (ReviewApiException e) {
                        return e.getMessage();
                    } finally {
                        status.setRollbackOnly();
                    }
                });
            });
            long start = System.nanoTime();
            try {
                assertThat(attempt.get(5, TimeUnit.SECONDS)).isEqualTo("error.case.locked");
                assertThat((System.nanoTime() - start) / 1_000_000_000.0).isBetween(2.0, 4.8);
            } catch (TimeoutException e) {
                throw new AssertionError("Waited for the lock more than 5 seconds instead of returning after 3", e);
            } finally {
                lock.rollback();
                attempt.get(2, TimeUnit.SECONDS);
            }
        } finally {
            executor.shutdownNow();
            try {
                assertThat(executor.awaitTermination(2, TimeUnit.SECONDS)).isTrue();
            } finally {
                removeFixture(id);
            }
        }
        assertThat(jdbc.sql("select count(*) from case_assignment").query(Long.class).single()).isEqualTo(assignments);
    }
    @Test
    @Timeout(15)
    @Transactional(propagation = Propagation.NOT_SUPPORTED)
    void competingDecisionsOnlyOneSucceedsInBothOrders() throws Exception {
        for (String first : java.util.List.of("CLOSE", "ESCALATE")) {
            long id = committedFixture();
            var winnerHasWritten = new java.util.concurrent.CountDownLatch(1);
            var contenderStarted = new java.util.concurrent.CountDownLatch(1);
            var executor = Executors.newFixedThreadPool(2);
            try {
                var winner = executor.submit(() -> new TransactionTemplate(transactionManager).execute(tx -> {
                    try {
                        service.decideCase(id, "manager_demo", first, "concurrent first", "IN_REVIEW");
                        winnerHasWritten.countDown();
                        assertThat(contenderStarted.await(3, TimeUnit.SECONDS)).isTrue();
                        // Commit within the 3-second lock limit so the second connection really gets the lock and rereads the committed state.
                        Thread.sleep(1000);
                        return state(id);
                    } catch (InterruptedException e) {
                        Thread.currentThread().interrupt();
                        throw new IllegalStateException(e);
                    } finally {
                        winnerHasWritten.countDown();
                    }
                }));
                var contender = executor.submit(() -> {
                    assertThat(winnerHasWritten.await(3, TimeUnit.SECONDS)).isTrue();
                    long start = System.nanoTime();
                    String message = new TransactionTemplate(transactionManager).execute(tx -> {
                        try {
                            contenderStarted.countDown();
                            service.decideCase(id, "manager_demo", first.equals("CLOSE") ? "ESCALATE" : "CLOSE",
                                "concurrent second", "IN_REVIEW");
                            return "SUCCESS";
                        } catch (ReviewApiException e) {
                            return e.getMessage();
                        } finally {
                            tx.setRollbackOnly();
                        }
                    });
                    assertThat((System.nanoTime() - start) / 1_000_000_000.0).isBetween(0.7, 2.9);
                    return message;
                });
                assertThat(contender.get(6, TimeUnit.SECONDS)).isEqualTo("error.case.stale");
                assertThat(winner.get(2, TimeUnit.SECONDS)).isEqualTo(first.equals("CLOSE") ? "CLOSED" : "ESCALATED");
                assertThat(state(id)).isEqualTo(first.equals("CLOSE") ? "CLOSED" : "ESCALATED");
                assertThat(jdbc.sql("select count(*) from review_decision where case_id = :id")
                    .param("id", id).query(Integer.class).single()).isEqualTo(1);
                assertThat(jdbc.sql("select count(*) from case_status_history where case_id = :id")
                    .param("id", id).query(Integer.class).single()).isEqualTo(4);
                assertThat(jdbc.sql("""
                    select count(*) from case_status_history h
                    left join case_status_transition t on t.from_status = h.from_status and t.to_status = h.to_status
                    where h.case_id = :id and h.from_status is not null and t.from_status is null
                    """).param("id", id).query(Integer.class).single()).isZero();
                System.out.println("Concurrency order " + first + ": first committed, second refused for stale state after waiting for the lock; 1 decision, 4 status history rows");
            } finally {
                executor.shutdownNow();
                try {
                    assertThat(executor.awaitTermination(3, TimeUnit.SECONDS)).isTrue();
                } finally {
                    removeFixture(id);
                }
            }
        }
    }

    @Test
    @Transactional(propagation = Propagation.NOT_SUPPORTED)
    void databaseFailureAfterDecisionInsertRollsBackWholeOperation() {
        long id = committedFixture();
        try {
            // On the second update the real Oracle status trigger rejects it, after the first-step decision INSERT has actually run.
            org.mockito.Mockito.doAnswer(invocation -> {
                jdbc.sql("update risk_review_case set current_status = 'INVALID_TEST' where case_id = :id")
                    .param("id", id).update();
                return null;
            }).when(repository).updateStatus(org.mockito.ArgumentMatchers.eq(id),
                org.mockito.ArgumentMatchers.eq("CLOSED"), org.mockito.ArgumentMatchers.anyLong());
            assertThatThrownBy(() -> service.decideCase(id, "manager_demo", "CLOSE", "whole operation rolled back after failure", "IN_REVIEW"))
                .isInstanceOf(org.springframework.dao.DataAccessException.class);
            assertThat(state(id)).isEqualTo("IN_REVIEW");
            assertThat(jdbc.sql("select count(*) from review_decision where case_id = :id")
                .param("id", id).query(Integer.class).single()).isZero();
            assertThat(jdbc.sql("select count(*) from case_status_history where case_id = :id")
                .param("id", id).query(Integer.class).single()).isEqualTo(3);
        } finally {
            org.mockito.Mockito.reset(repository);
            removeFixture(id);
        }
    }

    @Test
    void noOpRequestsCannotBypassWorkflow() {
        long id = open();
        assertThatThrownBy(() -> service.addAnnotation(id, "analyst_demo", "not assigned: no status change, and still not allowed"))
            .isInstanceOf(ReviewApiException.class).hasMessage("error.note.notAssigned");
        assertThat(state(id)).isEqualTo("OPEN");
        assertThat(jdbc.sql("select count(*) from case_annotation where case_id = :id")
            .param("id", id).query(Integer.class).single()).isZero();
        service.assignCase(id, userId("analyst_demo"), "manager_demo");
        service.addAnnotation(id, "analyst_demo", "assigned, may write");
        decide(id, "manager_demo", "ESCALATE");
        // Escalating an escalated case changes no status, and must still reject the wrong role before the illegal transition.
        assertThatThrownBy(() -> decide(id, "analyst_demo", "ESCALATE"))
            .isInstanceOf(ReviewApiException.class).hasMessage("error.decide.managerOnly");
        assertThatThrownBy(() -> decide(id, "manager_demo", "ESCALATE"))
            .isInstanceOf(ReviewApiException.class).hasMessage("error.decide.notAllowed");
        assertThat(state(id)).isEqualTo("ESCALATED");
        assertThat(jdbc.sql("select count(*) from review_decision where case_id = :id")
            .param("id", id).query(Integer.class).single()).isEqualTo(1);
        assertThat(jdbc.sql("select count(*) from case_status_history where case_id = :id")
            .param("id", id).query(Integer.class).single()).isEqualTo(4);
    }

    private long committedFixture() {
        return new TransactionTemplate(transactionManager).execute(status -> {
            String loan = "J" + Long.toString(System.nanoTime()).substring(5);
            loan = loan.substring(0, Math.min(12, loan.length()));
            jdbc.sql("""
                insert into review_candidate (rule_version_id, data_source, loan_identifier,
                    reporting_month, delinquency_status, source_release_id, candidate_source)
                select min(rule_version_id), 'FRE', :loan, date '2099-01-01', '2', 'R47', 'TEST'
                from review_rule_version
                """).param("loan", loan).update();
            long candidate = jdbc.sql("select candidate_id from review_candidate where loan_identifier = :loan")
                .param("loan", loan).query(Long.class).single();
            long id = service.openCase(candidate, "analyst_demo");
            service.assignCase(id, userId("analyst_demo"), "manager_demo");
            service.addAnnotation(id, "analyst_demo", "dedicated concurrency fixture");
            return id;
        });
    }

    private void removeFixture(long id) {
        new TransactionTemplate(transactionManager).executeWithoutResult(status -> {
            long candidate = jdbc.sql("select candidate_id from risk_review_case where case_id = :id")
                .param("id", id).query(Long.class).single();
            // Fixed table names, no user input; cleans only this test's cases and candidates.
            for (String table : java.util.List.of("case_assignment", "case_annotation", "review_decision", "case_status_history")) {
                jdbc.sql("delete from " + table + " where case_id = :id").param("id", id).update();
            }
            jdbc.sql("delete from risk_review_case where case_id = :id").param("id", id).update();
            jdbc.sql("delete from review_candidate where candidate_id = :id").param("id", candidate).update();
        });
        assertThat(jdbc.sql("select count(*) from risk_review_case where case_id = :id")
            .param("id", id).query(Integer.class).single()).isZero();
    }

}
