package com.loandw.review;

import static org.assertj.core.api.Assertions.assertThat;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.get;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

import java.nio.charset.StandardCharsets;

import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Nested;
import org.junit.jupiter.api.Tag;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.boot.webmvc.test.autoconfigure.AutoConfigureMockMvc;
import org.springframework.test.context.ActiveProfiles;
import org.springframework.test.web.servlet.MockMvc;

/**
 * Footer version: with build information the login page shows the short commit; without it (tests or IDE runs) the page works as usual without a version.
 * Connects to the test database only because starting the web application needs a data source; reads and writes no data.
 */
@Tag("db")
class AppVersionWebTest {

    private static String loginPage(MockMvc mvc) throws Exception {
        return mvc.perform(get("/login").header("Accept-Language", "zh-CN")).andExpect(status().isOk())
            .andReturn().getResponse().getContentAsString(StandardCharsets.UTF_8);
    }

    @Nested
    @ActiveProfiles("test")
    @SpringBootTest(properties = "spring.info.build.location=classpath:test-build-info.properties")
    @AutoConfigureMockMvc
    class WithBuildInfo {
        @Autowired
        private MockMvc mvc;

        @Test
        @DisplayName("With build information: the footer shows Version 0123456")
        void showsVersion() throws Exception {
            assertThat(loginPage(mvc)).contains("Version 0123456").doesNotContain("-dirty");
        }
    }

    @Nested
    @ActiveProfiles("test")
    @SpringBootTest(properties = "spring.info.build.location=classpath:no-such-build-info.properties")
    @AutoConfigureMockMvc
    class WithoutBuildInfo {
        @Autowired
        private MockMvc mvc;

        @Test
        @DisplayName("Without build information: the login page opens normally without a version")
        void pageStillWorks() throws Exception {
            assertThat(loginPage(mvc)).contains("<footer").doesNotContain("Version ");
        }
    }
}
