package com.loandw.review.web;

import org.springframework.context.MessageSource;
import org.springframework.context.i18n.LocaleContextHolder;
import org.springframework.stereotype.Component;

import com.loandw.review.repository.ReviewApiException;

/** Get message text in the current interface language (messages.properties) for controllers' success and failure messages. */
@Component
public class UiMessages {

    private final MessageSource messages;

    public UiMessages(MessageSource messages) {
        this.messages = messages;
    }

    public String get(String code, Object... args) {
        return messages.getMessage(code, args, LocaleContextHolder.getLocale());
    }

    /** Text of a business rejection: coded rejections are translated by code; errors raised directly by database triggers are translated by db.error.<number>, or shown as the database text if there is no translation. */
    public String of(ReviewApiException e) {
        if (e.getCode() != null) {
            return get(e.getCode(), e.getArgs());
        }
        return messages.getMessage("db.error." + e.getDbErrorCode(), e.getArgs(), e.getMessage(),
            LocaleContextHolder.getLocale());
    }
}
