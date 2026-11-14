package com.loandw.review.web;

import java.net.URI;
import java.util.Locale;

import jakarta.servlet.http.HttpServletRequest;

import org.springframework.context.i18n.LocaleContextHolder;
import org.springframework.security.core.Authentication;
import org.springframework.web.bind.annotation.ControllerAdvice;
import org.springframework.web.bind.annotation.ModelAttribute;
import org.springframework.web.util.UriComponentsBuilder;

import com.loandw.review.config.AppVersion;

/**
 * Shared information every page needs: current user name and whether the user is a manager (decides which buttons appear; real permission checks are in SecurityConfig and the service layer),
 * the language link, and the code version in the footer.
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

    /**
     * Language link: the current page plus lang=en or lang=zh, keeping other query parameters (such as the candidate month filter).
     * A page shown after a form submission (POST) has no GET page at the same address, so the referring page is used (Referer, this site only), otherwise the home page.
     */
    @ModelAttribute("switchLangUrl")
    public String switchLangUrl(HttpServletRequest request) {
        String target = Locale.ENGLISH.getLanguage().equals(LocaleContextHolder.getLocale().getLanguage()) ? "zh" : "en";
        String base = request.getRequestURI() + (request.getQueryString() == null ? "" : "?" + request.getQueryString());
        if (!"GET".equals(request.getMethod())) {
            base = sameSitePath(request.getHeader("Referer"), request);
        }
        return UriComponentsBuilder.fromUriString(base).replaceQueryParam("lang", target).build().toUriString();
    }

    private static String sameSitePath(String referer, HttpServletRequest request) {
        try {
            URI uri = referer == null ? null : URI.create(referer);
            if (uri != null && request.getServerName().equals(uri.getHost()) && uri.getRawPath() != null) {
                return uri.getRawPath() + (uri.getRawQuery() == null ? "" : "?" + uri.getRawQuery());
            }
        } catch (IllegalArgumentException e) {
            // Malformed referring address: go to the home page
        }
        return request.getContextPath() + "/";
    }
}
