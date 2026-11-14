package com.loandw.review.web;

import org.springframework.stereotype.Controller;
import org.springframework.ui.Model;
import org.springframework.web.bind.annotation.GetMapping;

import com.loandw.review.repository.ReviewRepository;

/**
 * Monthly review report (for both roles): reads the warehouse report view rpt_review_case_monthly, not OLTP.
 * So a case just closed appears here only after the next incremental extraction (source/dwd/run_cdc_review.sql); the page states the data's as-of time.
 */
@Controller
public class ReportController {

    private final ReviewRepository repo;

    public ReportController(ReviewRepository repo) {
        this.repo = repo;
    }

    @GetMapping("/reports")
    public String report(Model model) {
        model.addAttribute("rows", repo.reviewReport());
        model.addAttribute("total", repo.reviewReportTotal());
        return "report";
    }
}
