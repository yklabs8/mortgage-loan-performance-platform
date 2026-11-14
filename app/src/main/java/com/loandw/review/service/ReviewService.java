package com.loandw.review.service;

import java.util.List;
import java.util.Optional;

import org.springframework.security.access.AccessDeniedException;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import com.loandw.review.repository.ReviewApiException;
import com.loandw.review.repository.ReviewRepository;
import com.loandw.review.repository.ReviewRepository.CaseDetail;

/**
 * Business operations of the review system.
 * <ul>
 *   <li>One transaction per write operation (@Transactional): everything here commits only if all succeed, otherwise all is rolled back
 *       (for example, if a close decision was inserted but the status change is not allowed, the decision row is rolled back too)</li>
 *   <li>Who can view a case and write notes: managers always; analysts only cases they opened or that are assigned to them.
 *       Hiding links on the page is not enough; someone editing the case number in the URL must be stopped too</li>
 *   <li>Role limits (only managers assign and decide) are enforced once by URL in SecurityConfig and again in the service layer from the current role in the database;
 *       which cases are visible also follows the current database role, not the role remembered at login (a manager whose role is revoked immediately sees only their own cases)</li>
 *   <li>Check order: checks about the user alone (role) run before locking the case, so unauthorized requests neither lock nor wait;
 *       checks about the case's current state (visibility, state seen on the page, already closed, transition allowed) run after the lock</li>
 * </ul>
 */
@Service
public class ReviewService {

    private final ReviewRepository repo;

    public ReviewService(ReviewRepository repo) {
        this.repo = repo;
    }

    @Transactional
    public long openCase(long candidateId, String username) {
        return repo.openCase(candidateId, repo.userId(username));
    }

    @Transactional
    public void assignCase(long caseId, long assigneeUserId, String managerUsername) {
        long managerId = repo.userId(managerUsername);
        requireRole(managerId, "MANAGER", "error.assign.managerOnly");
        requireRole(assigneeUserId, "ANALYST", "error.assign.analystOnly");
        String status = lockOpenCase(caseId);
        String target = "OPEN".equals(status) ? "ASSIGNED" : status;
        checkTransition(status, target);
        repo.insertAssignment(caseId, assigneeUserId, managerId);
        repo.updateStatus(caseId, target, managerId);
    }

    @Transactional
    public void addAnnotation(long caseId, String username, String note) {
        long userId = repo.userId(username);
        String status = repo.lockCase(caseId);
        // The assignment may have just changed; visibility is decided inside the lock
        checkCanSee(caseId, userId);
        rejectTerminal(caseId, status, false);
        if (!List.of("ASSIGNED", "IN_REVIEW", "ESCALATED").contains(status)) {
            throw new ReviewApiException("error.note.notAssigned", String.valueOf(caseId));
        }
        String target = "ASSIGNED".equals(status) ? "IN_REVIEW" : status;
        checkTransition(status, target);
        repo.insertAnnotation(caseId, userId, note.trim());
        repo.updateStatus(caseId, target, userId);
    }

    @Transactional
    public void decideCase(long caseId, String managerUsername, String decisionType, String note,
                           String expectedStatus) {
        long managerId = repo.userId(managerUsername);
        requireRole(managerId, "MANAGER", "error.decide.managerOnly");
        String status = repo.lockCase(caseId);
        // Compare the state seen on the page while holding the lock; serializing two stale-page requests is not enough.
        if (!status.equals(expectedStatus)) {
            throw new ReviewApiException("error.case.stale");
        }
        rejectTerminal(caseId, status, "REOPEN".equals(decisionType));
        String target = switch (decisionType) {
            case "CLOSE" -> "CLOSED";
            case "ESCALATE" -> "ESCALATED";
            case "REOPEN" -> "IN_REVIEW";
            default -> throw new ReviewApiException("error.decide.badType", decisionType);
        };
        if (!repo.allowsTransition(status, target)) {
            throw new ReviewApiException("error.decide.notAllowed", status, target);
        }
        repo.insertDecision(caseId, managerId, decisionType, note.trim());
        repo.updateStatus(caseId, target, managerId);
    }

    private String lockOpenCase(long caseId) {
        String status = repo.lockCase(caseId);
        rejectTerminal(caseId, status, false);
        return status;
    }

    private void rejectTerminal(long caseId, String status, boolean allowClosed) {
        if (repo.isTerminal(status) && !allowClosed) {
            throw new ReviewApiException("error.case.closed", String.valueOf(caseId));
        }
    }

    private void requireRole(long userId, String role, String code) {
        if (!repo.hasRole(userId, role)) {
            throw new ReviewApiException(code);
        }
    }

    private void checkTransition(String from, String to) {
        if (!from.equals(to) && !repo.allowsTransition(from, to)) {
            throw new ReviewApiException("error.case.badTransition", from, to);
        }
    }

    /** Case detail; empty if the case does not exist, 403 if the user may not see it. */
    public Optional<CaseDetail> visibleCase(long caseId, String username) {
        Optional<CaseDetail> detail = repo.caseDetail(caseId);
        if (detail.isPresent()) {
            checkCanSee(caseId, repo.userId(username));
        }
        return detail;
    }

    /** Case list: managers (by current database role) see all, everyone else only cases they opened or that are assigned to them. */
    public List<ReviewRepository.CaseRow> cases(String username) {
        long userId = repo.userId(username);
        return repo.cases(userId, repo.hasRole(userId, "MANAGER"));
    }

    private void checkCanSee(long caseId, long userId) {
        if (!repo.hasRole(userId, "MANAGER") && !repo.canSee(caseId, userId)) {
            throw new AccessDeniedException("This case was not opened by you and is not assigned to you");
        }
    }
}
