package com.loandw.review.security;

import java.util.List;

import org.springframework.jdbc.core.simple.JdbcClient;
import org.springframework.security.core.authority.SimpleGrantedAuthority;
import org.springframework.security.core.userdetails.User;
import org.springframework.security.core.userdetails.UserDetails;
import org.springframework.security.core.userdetails.UserDetailsService;
import org.springframework.security.core.userdetails.UsernameNotFoundException;
import org.springframework.stereotype.Service;

/**
 * Reads login users from OLTP app_user and user_role: user name, password hash, active flag, roles.
 * Roles become Spring Security's ROLE_ANALYST and ROLE_MANAGER. Inactive users, users without a password, and users without a business role cannot log in;
 * users whose lock has not expired get "locked" (see {@link LoginAttemptService}).
 */
@Service
public class OltpUserDetailsService implements UserDetailsService {

    private final JdbcClient jdbc;

    public OltpUserDetailsService(JdbcClient jdbc) {
        this.jdbc = jdbc;
    }

    /** One user in the database. */
    private record UserRow(String username, String passwordHash, String isActive, String isLocked) {
    }

    @Override
    public UserDetails loadUserByUsername(String username) {
        UserRow row = jdbc.sql("""
                select username, password_hash, is_active
                   , case when locked_until > sys_extract_utc(systimestamp) then 'Y' else 'N' end as is_locked
                from app_user
                where username = :username
                """)
            .param("username", username)
            .query(UserRow.class)
            .optional()
            .orElseThrow(() -> new UsernameNotFoundException("No such user"));
        List<SimpleGrantedAuthority> roles = jdbc.sql("""
                select r.role_code
                from user_role ur
                inner join app_role r on ur.role_id = r.role_id
                inner join app_user u on ur.user_id = u.user_id
                where u.username = :username
                """)
            .param("username", username)
            .query(String.class)
            .list()
            .stream()
            .map(code -> new SimpleGrantedAuthority("ROLE_" + code))
            .toList();
        boolean canLogin = "Y".equals(row.isActive()) && row.passwordHash() != null && !roles.isEmpty();
        return User.withUsername(row.username())
            // Without a password, use a value that never matches and disable the account
            .password(row.passwordHash() != null ? row.passwordHash() : "{noop}-")
            .authorities(roles)
            .disabled(!canLogin)
            .accountLocked("Y".equals(row.isLocked()))
            .build();
    }
}
