package com.loandw.review;

import static org.assertj.core.api.Assertions.assertThat;
import static org.springframework.security.test.web.servlet.request.SecurityMockMvcRequestBuilders.formLogin;
import static org.springframework.security.test.web.servlet.request.SecurityMockMvcRequestPostProcessors.csrf;
import static org.springframework.security.test.web.servlet.request.SecurityMockMvcRequestPostProcessors.user;
import static org.springframework.security.test.web.servlet.response.SecurityMockMvcResultMatchers.authenticated;
import static org.springframework.security.test.web.servlet.response.SecurityMockMvcResultMatchers.unauthenticated;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.post;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.flash;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.model;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.redirectedUrl;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Tag;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.boot.webmvc.test.autoconfigure.AutoConfigureMockMvc;
import org.springframework.jdbc.core.simple.JdbcClient;
import org.springframework.security.crypto.password.PasswordEncoder;
import org.springframework.test.web.servlet.MockMvc;
import org.springframework.test.web.servlet.ResultActions;
import org.springframework.transaction.annotation.Transactional;

/**
 * Self-service password change and lockout after repeated wrong passwords.
 * Connects to the test database; each test runs in one transaction that is rolled back, so demo account passwords and lock state are unchanged.
 * Run: scripts/12_run_app.sh test
 */
@Tag("db")
@org.springframework.test.context.ActiveProfiles("test")
@SpringBootTest
@AutoConfigureMockMvc
@Transactional
class PasswordWebTest {

    private static final String ANALYST = "analyst_demo";
    private static final String OLD = "old-pass-for-test-1";
    private static final String NEW = "new-pass-for-test-2";

    @Autowired
    private MockMvc mvc;
    @Autowired
    private JdbcClient jdbc;
    @Autowired
    private PasswordEncoder encoder;

    @BeforeEach
    void knownPassword() {
        jdbc.sql("""
                update app_user set password_hash = :h, failed_login_count = 0, locked_until = null
                where username = :u
                """)
            .param("h", encoder.encode(OLD))
            .param("u", ANALYST)
            .update();
    }

    private ResultActions change(String oldPassword, String newPassword, String confirm) throws Exception {
        return mvc.perform(post("/account/password").with(user(ANALYST).roles("ANALYST")).with(csrf())
            .param("oldPassword", oldPassword)
            .param("newPassword", newPassword)
            .param("confirmPassword", confirm));
    }

    private String hash() {
        return jdbc.sql("select password_hash from app_user where username = :u")
            .param("u", ANALYST).query(String.class).single();
    }

    private int failures() {
        return jdbc.sql("select failed_login_count from app_user where username = :u")
            .param("u", ANALYST).query(Integer.class).single();
    }

    @Test
    @DisplayName("Change password: with the right old password the BCrypt hash of the new one is stored; the new password then logs in and the old one does not")
    void changePassword() throws Exception {
        change(OLD, NEW, NEW)
            .andExpect(redirectedUrl("/account/password"))
            .andExpect(flash().attribute("message", "Password changed. Use the new password next time you sign in."));
        assertThat(hash()).startsWith("$2").doesNotContain(NEW);
        assertThat(jdbc.sql("select count(*) from app_user where username = :u and password_changed_at is not null")
            .param("u", ANALYST).query(Integer.class).single()).isEqualTo(1);
        mvc.perform(formLogin("/login").user(ANALYST).password(NEW)).andExpect(authenticated());
        mvc.perform(formLogin("/login").user(ANALYST).password(OLD)).andExpect(unauthenticated());
    }

    @Test
    @DisplayName("Change password: wrong old password, new password breaking the rules, mismatched confirmation, or same as old changes nothing and says why")
    void rejectBadInput() throws Exception {
        String before = hash();
        change("wrong-old-password-1", NEW, NEW).andExpect(model().attribute("error",
            "Current password is incorrect (five failures in a row lock the account for 15 minutes)"));
        assertThat(failures()).isEqualTo(1);
        change(OLD, "short1", "short1").andExpect(model().attributeHasFieldErrors("passwordForm", "newPassword"));
        change(OLD, "no-digits-at-all", "no-digits-at-all")
            .andExpect(model().attributeHasFieldErrors("passwordForm", "newPassword"));
        change(OLD, "éééééééééééé1a", "éééééééééééé1a")
            .andExpect(model().attributeHasFieldErrors("passwordForm", "newPassword"));
        change(OLD, NEW, NEW + "x").andExpect(model().attributeHasFieldErrors("passwordForm", "confirmed"));
        change(OLD, OLD, OLD).andExpect(model().attribute("error", "The new password must differ from the current one"));
        assertThat(hash()).isEqualTo(before);
    }

    @Test
    @DisplayName("Changing the password requires a CSRF token; without one the answer is 403")
    void changeNeedsCsrf() throws Exception {
        mvc.perform(post("/account/password").with(user(ANALYST).roles("ANALYST"))
                .param("oldPassword", OLD).param("newPassword", NEW).param("confirmPassword", NEW))
            .andExpect(status().isForbidden());
    }

    @Test
    @DisplayName("5 wrong logins in a row lock the account: while locked even the right password fails; after expiry login works and the count resets")
    void lockAfterFiveFailures() throws Exception {
        for (int i = 1; i <= 4; i++) {
            mvc.perform(formLogin("/login").user(ANALYST).password("wrong-" + i))
                .andExpect(redirectedUrl("/login?error"));
            assertThat(failures()).isEqualTo(i);
        }
        mvc.perform(formLogin("/login").user(ANALYST).password("wrong-5"));
        mvc.perform(formLogin("/login").user(ANALYST).password(OLD))
            .andExpect(unauthenticated())
            .andExpect(redirectedUrl("/login?locked"));
        assertThat(failures()).isZero();  // reset on locking, and attempts while locked are not counted

        jdbc.sql("update app_user set locked_until = sys_extract_utc(systimestamp) - interval '1' second where username = :u")
            .param("u", ANALYST).update();
        mvc.perform(formLogin("/login").user(ANALYST).password(OLD)).andExpect(authenticated());
        assertThat(jdbc.sql("select count(*) from app_user where username = :u and locked_until is null")
            .param("u", ANALYST).query(Integer.class).single()).isEqualTo(1);
    }

    @Test
    @DisplayName("A successful login after a few wrong ones resets the count")
    void successResetsCount() throws Exception {
        mvc.perform(formLogin("/login").user(ANALYST).password("wrong-1"));
        mvc.perform(formLogin("/login").user(ANALYST).password("wrong-2"));
        assertThat(failures()).isEqualTo(2);
        mvc.perform(formLogin("/login").user(ANALYST).password(OLD)).andExpect(authenticated());
        assertThat(failures()).isZero();
    }

    @Test
    @DisplayName("The old password on the change page counts too: 5 wrong in a row lock the account and log out, so it cannot bypass the login lockout")
    void oldPasswordGuessingLocks() throws Exception {
        for (int i = 1; i <= 4; i++) {
            change("wrong-old-" + i, NEW, NEW).andExpect(status().isOk());
        }
        change("wrong-old-5", NEW, NEW).andExpect(redirectedUrl("/login?locked"));
        change(OLD, NEW, NEW).andExpect(redirectedUrl("/login?locked"));  // locked, so nothing changes even with the right old password
        mvc.perform(formLogin("/login").user(ANALYST).password(OLD)).andExpect(redirectedUrl("/login?locked"));
    }

    @Test
    @DisplayName("Password changes are logged: one OK line on success, one REJECTED line with the code for a wrong old password; no password ever appears in the log")
    @org.junit.jupiter.api.extension.ExtendWith(org.springframework.boot.test.system.OutputCaptureExtension.class)
    void passwordChangeIsLoggedWithoutPasswords(org.springframework.boot.test.system.CapturedOutput output) throws Exception {
        change("wrong-old-for-log", NEW, NEW);
        change(OLD, NEW, NEW);
        assertThat(output.getOut())
            .contains("action=PASSWORD user=" + ANALYST + " result=REJECTED code=password.wrongOld")
            .contains("action=PASSWORD user=" + ANALYST + " result=OK")
            .doesNotContain("wrong-old-for-log").doesNotContain(OLD).doesNotContain(NEW);
    }
}
