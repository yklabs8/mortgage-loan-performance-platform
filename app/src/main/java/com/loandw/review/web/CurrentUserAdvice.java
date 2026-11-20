package com.loandw.review.web;

import org.springframework.security.core.Authentication;
import org.springframework.web.bind.annotation.ControllerAdvice;
import org.springframework.web.bind.annotation.ModelAttribute;

import com.loandw.review.config.AppVersion;

/**
 * Shared information every page needs: current user name and whether the user is a manager (decides which buttons appear; real permission checks are in SecurityConfig and the service layer),
 * and the code version in the footer.
 */
@ControllerAdvice
public class CurrentUserAdvice {

    private final AppVersion version;

    public CurrentUserAdvice(AppVersion version) {
        this.version = version;
    }

    @ModelAttribute("appVersion")
    public String appVersion() {
        return version.label();
    }

    @ModelAttribute("username")
    public String username(Authentication auth) {
        return auth == null ? null : auth.getName();
    }

    @ModelAttribute("isManager")
    public boolean manager(Authentication auth) {
        return isManager(auth);
    }

    public static boolean isManager(Authentication auth) {
        return auth != null && auth.getAuthorities().stream()
            .anyMatch(a -> "ROLE_MANAGER".equals(a.getAuthority()));
    }
}
