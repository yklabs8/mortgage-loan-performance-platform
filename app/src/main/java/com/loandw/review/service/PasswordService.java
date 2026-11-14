package com.loandw.review.service;

import org.springframework.jdbc.core.simple.JdbcClient;
import org.springframework.security.crypto.password.PasswordEncoder;
import org.springframework.stereotype.Service;

import com.loandw.review.security.LoginAttemptService;

/**
 * Self-service password change: verify the old password first, then store the BCrypt hash of the new one.
 * <ul>
 *   <li>A wrong old password counts like a wrong login and locks at 5: the password page cannot be used to bypass the login lockout and guess passwords</li>
 *   <li>The write is conditioned on the old hash that was read (update ... where password_hash = old hash):
 *       if two pages change it at once, only one succeeds and the other is asked to refresh, the same concurrency rule as review decisions</li>
 *   <li>Rules for the new password (length, characters) are form validation; only "must differ from the old password" is checked here, because it needs the old hash</li>
 * </ul>
 */
@Service
public class PasswordService {

    /** Result of a password change. */
    public enum Result { CHANGED, WRONG_OLD_PASSWORD, LOCKED, SAME_AS_OLD, CONFLICT }

    private final JdbcClient jdbc;
    private final PasswordEncoder encoder;
    private final LoginAttemptService attempts;

    public PasswordService(JdbcClient jdbc, PasswordEncoder encoder, LoginAttemptService attempts) {
        this.jdbc = jdbc;
        this.encoder = encoder;
        this.attempts = attempts;
    }

    public Result change(String username, String oldPassword, String newPassword) {
        if (attempts.isLocked(username)) {
            return Result.LOCKED;
        }
        String currentHash = jdbc.sql("select password_hash from app_user where username = :username")
            .param("username", username)
            .query(String.class)
            .optional()
            .orElse(null);
        if (currentHash == null || !encoder.matches(oldPassword, currentHash)) {
            return attempts.recordFailure(username) ? Result.LOCKED : Result.WRONG_OLD_PASSWORD;
        }
        if (encoder.matches(newPassword, currentHash)) {
            return Result.SAME_AS_OLD;
        }
        int rows = jdbc.sql("""
                update app_user
                set password_hash = :newHash, password_changed_at = systimestamp
                    , failed_login_count = 0, locked_until = null
                where username = :username and password_hash = :currentHash
                """)
            .param("newHash", encoder.encode(newPassword))
            .param("username", username)
            .param("currentHash", currentHash)
            .update();
        return rows == 1 ? Result.CHANGED : Result.CONFLICT;
    }
}
