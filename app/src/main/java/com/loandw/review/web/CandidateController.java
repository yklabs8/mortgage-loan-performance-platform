package com.loandw.review.web;

import org.springframework.security.core.Authentication;
import org.springframework.stereotype.Controller;
import org.springframework.ui.Model;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.servlet.mvc.support.RedirectAttributes;

import com.loandw.review.repository.ReviewApiException;
import com.loandw.review.repository.ReviewRepository;
import com.loandw.review.service.ReviewService;

/** Review candidates: the delivered candidate list, evidence detail, and opening a case; generation is done by the pipeline. */
@Controller
@RequestMapping("/candidates")
public class CandidateController {

    private final ReviewRepository repo;
    private final ReviewService service;
    private final UiMessages ui;

    public CandidateController(ReviewRepository repo, ReviewService service, UiMessages ui) {
        this.repo = repo;
        this.service = service;
        this.ui = ui;
    }

    @GetMapping
    public String list(@RequestParam(required=false) String loan,
        @RequestParam(required=false) String month,
        @RequestParam(defaultValue="50") int size,
        @RequestParam(required=false) String after, Model model) {
        try {
            if (after != null && after.length() > 100) throw new IllegalArgumentException("Cursor too long");
            var reportingMonth = month == null || month.isBlank() ? null : java.time.YearMonth.parse(month).atDay(1);
            var rows = repo.candidates(loan, reportingMonth, size, after);
            boolean more = rows.size() > size;
            var page = more ? rows.subList(0, size) : rows;
            model.addAttribute("candidates", page);
            model.addAttribute("next", more ? repo.candidateCursor(page.get(page.size()-1).candidateId()) : null);
        } catch (IllegalArgumentException | java.time.DateTimeException e) {
            throw new org.springframework.web.server.ResponseStatusException(
                org.springframework.http.HttpStatus.BAD_REQUEST, "Invalid month or paging parameter");
        }
        model.addAttribute("loan", loan);
        model.addAttribute("month", month);
        model.addAttribute("size", size);
        return "candidates";
    }

    @GetMapping("/{candidateId}")
    public String detail(@PathVariable long candidateId, Model model) {
        var candidate = repo.candidate(candidateId).orElseThrow(() ->
            new org.springframework.web.server.ResponseStatusException(org.springframework.http.HttpStatus.NOT_FOUND));
        Long id = repo.latestEvidence(candidateId);
        model.addAttribute("c", candidate);
        model.addAttribute("evidence", repo.evidence(id).orElse(null));
        model.addAttribute("loanInfo", repo.loanInfo(id).orElse(null));
        model.addAttribute("months", repo.recentMonths(id, candidate.reportingMonth()));
        return "candidate";
    }

    @PostMapping("/{candidateId}/open")
    public String open(@PathVariable long candidateId, Authentication auth, RedirectAttributes redirect) {
        try {
            long caseId = service.openCase(candidateId, auth.getName());
            // The service method has committed when it returns (see OperationLog)
            OperationLog.ok("OPEN", auth.getName(), "candidate=" + candidateId);
            redirect.addFlashAttribute("message", ui.get("done.opened"));
            return "redirect:/cases/" + caseId;
        } catch (ReviewApiException e) {
            OperationLog.rejected("OPEN", auth.getName(), "candidate=" + candidateId, OperationLog.code(e));
            redirect.addFlashAttribute("error", ui.of(e));
            return "redirect:/candidates";
        }
    }
}
