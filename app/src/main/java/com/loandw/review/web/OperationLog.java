package com.loandw.review.web;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;

import com.loandw.review.repository.ReviewApiException;

/**
 * Write-operation log: one INFO line per open, assign, note, decision, and password change.
 * <ul>
 *   <li>Format action=... user=... [case=...|candidate=...] result=OK|REJECTED [code=message code], easy to grep by field; password changes have no case number</li>
 *   <li>Called by controllers after the service method returns: the service method is the transaction boundary, so a failed commit never leaves an OK</li>
 *   <li>Note text, decision reasons, and passwords are never logged</li>
 * </ul>
 */
final class OperationLog {

    private static final Logger LOG = LoggerFactory.getLogger(OperationLog.class);

    private OperationLog() {
    }

    static void ok(String action, String user, String target) {
        LOG.info("action={} user={}{} result=OK", action, user, prefixed(target));
    }

    static void rejected(String action, String user, String target, String code) {
        LOG.info("action={} user={}{} result=REJECTED code={}", action, user, prefixed(target), code);
    }

    private static String prefixed(String target) {
        return target.isEmpty() ? "" : " " + target;
    }

    /** Message code of a business rejection; business errors raised by database triggers have no code, so the error number is logged. */
    static String code(ReviewApiException e) {
        return e.getCode() != null ? e.getCode() : "db." + e.getDbErrorCode();
    }
}
