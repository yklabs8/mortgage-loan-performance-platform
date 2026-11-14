package com.loandw.review.security;

import org.springframework.context.event.EventListener;
import org.springframework.jdbc.core.simple.JdbcClient;
import org.springframework.security.authentication.event.AuthenticationFailureBadCredentialsEvent;
import org.springframework.security.authentication.event.AuthenticationSuccessEvent;
import org.springframework.stereotype.Service;

/**
 * Lockout after repeated wrong passwords: {@value #MAX_FAILURES} wrong passwords in a row
 * lock the account for {@value #LOCK_MINUTES} minutes; a successful login resets the count.
 * <ul>
 *   <li>The count and the lock are computed by the database in one update: two simultaneous wrong attempts cannot both read the old count and lose one</li>
 *   <li>Locking resets the count: after the lock expires there are 5 new attempts, instead of locking again after one more mistake</li>
 *   <li>While locked, Spring Security reports "locked" first and no longer compares passwords, so attempts during the lock are not counted and cannot guess the password</li>
 *   <li>An unknown user name updates 0 rows and records nothing</li>
 *   <li>The lock expiry is stored and compared in UTC: the database clock (systimestamp carries the container's time zone) and the web connection's session time zone differ,
 *       and comparing a column without time zone directly with systimestamp would be off by hours</li>
 * </ul>
 */
@Service
public class LoginAttemptService {

    public static final int MAX_FAILURES = 5;
    public static final int LOCK_MINUTES = 15;

    private final JdbcClient jdbc;

    public LoginAttemptService(JdbcClient jdbc) {
        this.jdbc = jdbc;
    }

    @EventListener
    public void onBadPassword(AuthenticationFailureBadCredentialsEvent event) {
        recordFailure(event.getAuthentication().getName());
    }

    @EventListener
    public void onSuccess(AuthenticationSuccessEvent event) {
        reset(event.getAuthentication().getName());
    }

    /** Record one wrong password; return whether the account is now locked. */
    public boolean recordFailure(String username) {
        jdbc.sql("""
                update app_user
                set locked_until = case when failed_login_count + 1 >= :max
                                        then sys_extract_utc(systimestamp) + numtodsinterval(:minutes, 'MINUTE')
                                        else locked_until end
                    , failed_login_count = case when failed_login_count + 1 >= :max
                                                then 0 else failed_login_count + 1 end
                where username = :username
                """)
            .param("max", MAX_FAILURES)
            .param("minutes", LOCK_MINUTES)
            .param("username", username)
            .update();
        return isLocked(username);
    }

    public boolean isLocked(String username) {
        return jdbc.sql("""
                select count(*) from app_user
                where username = :username and locked_until > sys_extract_utc(systimestamp)
                """)
            .param("username", username)
            .query(Integer.class)
            .single() > 0;
    }

    /** Reset; skip the write when already zero, so a login does not touch updated_at every time. */
    private void reset(String username) {
        jdbc.sql("""
                update app_user
                set failed_login_count = 0, locked_until = null
                where username = :username
                   and (failed_login_count > 0 or locked_until is not null)
                """)
            .param("username", username)
            .update();
    }
}
