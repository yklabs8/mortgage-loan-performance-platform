package com.loandw.review.web;

import org.springframework.stereotype.Controller;
import org.springframework.ui.Model;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RequestParam;
import com.loandw.review.repository.ReviewRepository;
@Controller
@RequestMapping("/candidates")
public class CandidateController {

    private final ReviewRepository repo;
    public CandidateController(ReviewRepository repo) {
        this.repo = repo;
    }
    
    @GetMapping
    public String list(@RequestParam(required = false) String loan, Model model) {
        model.addAttribute("loan", loan);
        model.addAttribute("candidates", repo.candidates(loan));
        return "candidates";
    }
}
