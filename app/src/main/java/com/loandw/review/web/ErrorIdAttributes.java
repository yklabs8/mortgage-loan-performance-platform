package com.loandw.review.web;

import java.security.Principal;
import java.util.Map;
import java.util.UUID;

import jakarta.servlet.http.HttpServletRequest;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.boot.web.error.ErrorAttributeOptions;
import org.springframework.boot.webmvc.error.DefaultErrorAttributes;
import org.springframework.stereotype.Component;
import org.springframework.web.context.request.NativeWebRequest;
import org.springframework.web.context.request.WebRequest;

/**
 * Error page attributes: on a system error (500 and above) an 8-character error ID errorId is added and the page shows only that ID;
 * one ERROR log line records the same ID, request method and path, user name, exception type, and stack trace, so a reported error can be found by ID.
 * Request problems such as 403, 404, and 400 get no ID and the page is unchanged.
 * No global @ExceptionHandler(Exception.class): it would also turn Spring Security's 403 and the not-found 404 into 500.
 */
@Component
public class ErrorIdAttributes extends DefaultErrorAttributes {

    private static final Logger LOG = LoggerFactory.getLogger(ErrorIdAttributes.class);

    @Override
    public Map<String, Object> getErrorAttributes(WebRequest webRequest, ErrorAttributeOptions options) {
        Map<String, Object> attributes = super.getErrorAttributes(webRequest, options);
        if (attributes.get("status") instanceof Integer status && status >= 500) {
            String id = UUID.randomUUID().toString().substring(0, 8);
            attributes.put("errorId", id);
            HttpServletRequest request = webRequest instanceof NativeWebRequest n
                ? n.getNativeRequest(HttpServletRequest.class) : null;
            Principal user = webRequest.getUserPrincipal();
            Throwable error = getError(webRequest);
            LOG.error("errorId={} {} {} user={} {}", id, request == null ? "-" : request.getMethod(),
                attributes.get("path"), user == null ? "-" : user.getName(),
                error == null ? "-" : error.getClass().getName(), error);
        }
        return attributes;
    }
}
