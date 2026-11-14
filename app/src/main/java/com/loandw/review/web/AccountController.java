package com.loandw.review.web;

import jakarta.servlet.http.HttpServletRequest;
import jakarta.servlet.http.HttpServletResponse;

import org.springframework.security.core.Authentication;
import org.springframework.security.web.authentication.logout.SecurityContextLogoutHandler;
import org.springframework.stereotype.Controller;
import org.springframework.ui.Model;
import org.springframework.validation.BindingResult;
import org.springframework.validation.annotation.Validated;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.ModelAttribute;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.servlet.mvc.support.RedirectAttributes;

import com.loandw.review.service.PasswordService;
import com.loandw.review.web.form.PasswordForm;

/** Self-service password change (for analysts and managers, only their own). If the old password is wrong too often and the account locks, the user is logged out at once. */
@Controller
public class AccountController {

    private final PasswordService service;
    private final UiMessages ui;

    public AccountController(PasswordService service, UiMessages ui) {
        this.service = service;
        this.ui = ui;
    }

    @GetMapping("/account/password")
    public String form(Model model) {
        model.addAttribute("passwordForm", new PasswordForm());
        return "password";
    }

    @PostMapping("/account/password")
    public String change(@Validated @ModelAttribute("passwordForm") PasswordForm form, BindingResult binding,
                         Authentication auth, Model model, RedirectAttributes redirect,
                         HttpServletRequest request, HttpServletResponse response) {
        if (binding.hasErrors()) {
            return "password";
        }
        // Each password-change statement commits automatically, so it is written when the call returns; the log records only the result, never the password (see OperationLog)
        String user = auth.getName();
        switch (service.change(user, form.getOldPassword(), form.getNewPassword())) {
            case CHANGED -> {
                OperationLog.ok("PASSWORD", user, "");
                redirect.addFlashAttribute("message", ui.get("password.changed"));
                return "redirect:/account/password";
            }
            case LOCKED -> {
                OperationLog.rejected("PASSWORD", user, "", "login.locked");
                new SecurityContextLogoutHandler().logout(request, response, auth);
                return "redirect:/login?locked";
            }
            case WRONG_OLD_PASSWORD -> reject(model, user, "password.wrongOld");
            case SAME_AS_OLD -> reject(model, user, "password.sameAsOld");
            case CONFLICT -> reject(model, user, "password.conflict");
        }
        return "password";
    }

    private void reject(Model model, String user, String code) {
        OperationLog.rejected("PASSWORD", user, "", code);
        model.addAttribute("error", ui.get(code));
    }
}
