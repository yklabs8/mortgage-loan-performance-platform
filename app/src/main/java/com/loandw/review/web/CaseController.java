package com.loandw.review.web;

import org.springframework.http.HttpStatus;
import org.springframework.security.access.AccessDeniedException;
import org.springframework.security.core.Authentication;
import org.springframework.stereotype.Controller;
import org.springframework.ui.Model;
import org.springframework.validation.BindingResult;
import org.springframework.validation.annotation.Validated;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.ModelAttribute;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.server.ResponseStatusException;
import org.springframework.web.servlet.mvc.support.RedirectAttributes;

import com.loandw.review.repository.ReviewApiException;
import com.loandw.review.repository.ReviewRepository;
import com.loandw.review.repository.ReviewRepository.CaseDetail;
import com.loandw.review.service.ReviewService;
import com.loandw.review.web.form.AssignForm;
import com.loandw.review.web.form.DecisionForm;
import com.loandw.review.web.form.NoteForm;

/**
 * Review cases: list, detail, assign (manager), add note, decide (manager).
 * Invalid form input returns to the detail page with the reason next to the form; business rejections show the reason (see UiMessages).
 */
@Controller
@RequestMapping("/cases")
public class CaseController {

    private final ReviewRepository repo;
    private final ReviewService service;
    private final UiMessages ui;

    public CaseController(ReviewRepository repo, ReviewService service, UiMessages ui) {
        this.repo = repo;
        this.service = service;
        this.ui = ui;
    }

    @GetMapping
    public String list(Authentication auth, Model model) {
        model.addAttribute("cases", service.cases(auth.getName()));
        return "cases";
    }

    @GetMapping("/{caseId}")
    public String detail(@PathVariable long caseId, Authentication auth, Model model) {
        CaseDetail detail = service.visibleCase(caseId, auth.getName())
            .orElseThrow(() -> new ResponseStatusException(HttpStatus.NOT_FOUND, "No such case"));
        var ref = repo.caseEvidence(caseId);
        model.addAttribute("evidence", repo.evidence(ref.evidenceId()).orElse(null));
        model.addAttribute("hasNewEvidence", ref.latestEvidenceId() != null
            && !ref.latestEvidenceId().equals(ref.evidenceId()));
        model.addAttribute("c", detail);
        model.addAttribute("loanInfo", repo.loanInfo(ref.evidenceId()).orElse(null));
        model.addAttribute("months",
            repo.recentMonths(ref.evidenceId(), detail.reportingMonth()));
        model.addAttribute("activities", repo.activities(caseId));
        // The role at login only decides whether manager drop-downs are shown; whether the user can view or act is decided by the service layer from the current database role
        if (CurrentUserAdvice.isManager(auth)) {
            model.addAttribute("analysts", repo.analysts());
        }
        // When a form error returns to this page, keep what the user entered and the error, instead of replacing it with an empty form
        if (!model.containsAttribute("assignForm")) {
            model.addAttribute("assignForm", new AssignForm());
        }
        if (!model.containsAttribute("noteForm")) {
            model.addAttribute("noteForm", new NoteForm());
        }
        if (!model.containsAttribute("decisionForm")) {
            DecisionForm form = new DecisionForm();
            form.setExpectedStatus(detail.currentStatus());
            model.addAttribute("decisionForm", form);
        }
        return "case";
    }

    @PostMapping("/{caseId}/assign")
    public String assign(@PathVariable long caseId, @Validated @ModelAttribute AssignForm assignForm,
                         BindingResult errors, Authentication auth, Model model, RedirectAttributes redirect) {
        if (errors.hasErrors()) {
            return detail(caseId, auth, model);
        }
        return runAndRedirect(caseId, auth, "ASSIGN", redirect, "done.assigned",
            () -> service.assignCase(caseId, assignForm.getAssigneeUserId(), auth.getName()));
    }

    @PostMapping("/{caseId}/annotate")
    public String annotate(@PathVariable long caseId, @Validated @ModelAttribute NoteForm noteForm,
                           BindingResult errors, Authentication auth, Model model, RedirectAttributes redirect) {
        if (errors.hasErrors()) {
            return detail(caseId, auth, model);
        }
        return runAndRedirect(caseId, auth, "NOTE", redirect, "done.noted",
            () -> service.addAnnotation(caseId, auth.getName(), noteForm.getNoteText()));
    }

    @PostMapping("/{caseId}/decide")
    public String decide(@PathVariable long caseId, @Validated @ModelAttribute DecisionForm decisionForm,
                         BindingResult errors, Authentication auth, Model model, RedirectAttributes redirect) {
        if (errors.hasErrors()) {
            return detail(caseId, auth, model);
        }
        // The form has already validated that the decision type is one of these three
        String done = "done.decision." + decisionForm.getDecisionType();
        return runAndRedirect(caseId, auth, "DECIDE_" + decisionForm.getDecisionType(), redirect, done,
            () -> service.decideCase(caseId, auth.getName(), decisionForm.getDecisionType(),
                decisionForm.getDecisionNote(), decisionForm.getExpectedStatus()));
    }

    /**
     * Run one write operation, return to the case detail page, and show a success message (message code doneCode) or the rejection reason.
     * The service method has committed when it returns, and only then is OK logged; business rejections and cases the user may not see (403) are logged as REJECTED (see OperationLog).
     */
    private String runAndRedirect(long caseId, Authentication auth, String operation, RedirectAttributes redirect,
                                  String doneCode, Runnable action) {
        String target = "case=" + caseId;
        try {
            action.run();
            OperationLog.ok(operation, auth.getName(), target);
            redirect.addFlashAttribute("message", ui.get(doneCode));
        } catch (ReviewApiException e) {
            OperationLog.rejected(operation, auth.getName(), target, OperationLog.code(e));
            redirect.addFlashAttribute("error", ui.of(e));
        } catch (AccessDeniedException e) {
            OperationLog.rejected(operation, auth.getName(), target, "error.403");
            throw e;
        }
        return "redirect:/cases/" + caseId;
    }
}
