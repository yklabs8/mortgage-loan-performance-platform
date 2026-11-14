package com.loandw.review.repository;

import java.sql.SQLException;

import org.springframework.dao.DataAccessException;

/**
 * A business rule rejected an operation; the message is shown to the user. Two sources:
 * <ul>
 *   <li>Service-layer role, status, and stale-page checks, plus database lock conflicts: a message code (a key in messages.properties) with arguments,
 *       translated for display (see web/UiMessages)</li>
 *   <li>Business errors raised by the status triggers kept in the database (reached only by bypassing Java): the error number and the database's original text
 *       (without ORA-xxxxx and the call stack); a db.error.<number> translation is used when one exists</li>
 * </ul>
 * getMessage() is the message code (or the database's own text), so tests assert on codes independent of the interface language.
 */
public class ReviewApiException extends RuntimeException {

    /**
     * ORA-01403 (no data found): a select into in review_api found nothing, for example a rule with no effective version this month; an empty result when Java locks a case uses the same message.
     * Normal page use never reaches it, only an edited URL; show a message instead of a 500 error page.
     */
    private static final int NO_DATA_FOUND = 1403;

    /** Range of business rule error codes (-20000 to -20999, as used by raise_application_error). */
    private static final int MIN_APP_ERROR = 20000;
    private static final int MAX_APP_ERROR = 20999;

    private final String code;
    private final Object[] args;
    private final int dbErrorCode;

    /** A business rejection with a message code. */
    public ReviewApiException(String code, Object... args) {
        super(code);
        this.code = code;
        this.args = args;
        this.dbErrorCode = 0;
    }

    private ReviewApiException(int dbErrorCode, String dbText, Throwable cause) {
        super(dbText, cause);
        this.code = null;
        this.args = new Object[0];
        this.dbErrorCode = dbErrorCode;
    }

    /** A business rejection with a known reason (for example a unique-constraint conflict meaning "a case is already open"). */
    public static ReviewApiException withCause(Throwable cause, String code, Object... args) {
        ReviewApiException e = new ReviewApiException(code, args);
        e.initCause(cause);
        return e;
    }

    public String getCode() {
        return code;
    }

    public Object[] getArgs() {
        return args.clone();
    }

    public int getDbErrorCode() {
        return dbErrorCode;
    }

    /** Database business rule errors become this exception; other errors (no connection, wrong SQL) are rethrown as is, never swallowed. */
    public static RuntimeException from(DataAccessException e) {
        // Walk the cause chain to the first SQLException: the Oracle driver wraps a non-SQLException OracleDatabaseException beneath it,
        // so getMostSpecificCause() (the deepest cause) cannot be used, as it has no error code
        SQLException sql = null;
        for (Throwable t = e; t != null && sql == null; t = t.getCause()) {
            if (t instanceof SQLException found) {
                sql = found;
            }
        }
        if (sql != null && (sql.getErrorCode() == 30006 || sql.getErrorCode() == 54)) {
            return withCause(e, "error.case.locked");
        }
        if (sql != null && sql.getErrorCode() == NO_DATA_FOUND) {
            return withCause(e, "error.notFound");
        }
        if (sql != null && sql.getErrorCode() >= MIN_APP_ERROR && sql.getErrorCode() <= MAX_APP_ERROR) {
            String text = sql.getMessage();
            // Shaped like "ORA-20014: case already closed: 3\nORA-06512: at ...": keep only the part after the first colon on the first line
            String firstLine = text.split("\n", 2)[0];
            int colon = firstLine.indexOf(": ");
            return new ReviewApiException(sql.getErrorCode(),
                colon >= 0 ? firstLine.substring(colon + 2) : firstLine, e);
        }
        return e;
    }
}
