package com.loandw.review;

import static org.assertj.core.api.Assertions.assertThat;
import static org.springframework.security.test.web.servlet.request.SecurityMockMvcRequestPostProcessors.user;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.get;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

import java.nio.charset.StandardCharsets;
import java.util.regex.Pattern;

import jakarta.servlet.RequestDispatcher;

import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Tag;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.boot.test.system.CapturedOutput;
import org.springframework.boot.test.system.OutputCaptureExtension;
import org.springframework.boot.webmvc.test.autoconfigure.AutoConfigureMockMvc;
import org.springframework.test.web.servlet.MockMvc;

/**
 * Error page IDs. MockMvc does not forward to the error page by itself, so this requests /error directly with the request attributes Tomcat sets on forwarding,
 * exercising the real error controller, the error attribute class (ErrorIdAttributes), and the error.html template.
 * Connects to the test database only because starting the web application needs a data source; reads and writes no data.
 */
@Tag("db")
@org.springframework.test.context.ActiveProfiles("test")
@SpringBootTest
@AutoConfigureMockMvc
@ExtendWith(OutputCaptureExtension.class)
class ErrorPageWebTest {

    private static final Pattern ID = Pattern.compile("Error ID: ([0-9a-f]{8})");

    @Autowired
    private MockMvc mvc;

    private String errorPage(int code, Throwable error) throws Exception {
        var request = get("/error").with(user("analyst_demo").roles("ANALYST"))
            .requestAttr(RequestDispatcher.ERROR_STATUS_CODE, code)
            .requestAttr(RequestDispatcher.ERROR_REQUEST_URI, "/cases/42")
            .accept("text/html");
        if (error != null) {
            request = request.requestAttr(RequestDispatcher.ERROR_EXCEPTION, error);
        }
        return mvc.perform(request).andExpect(status().is(code))
            .andReturn().getResponse().getContentAsString(StandardCharsets.UTF_8);
    }

    @Test
    @DisplayName("500: the page shows only the 8-character ID, not the exception; the log has one ERROR line with the same ID, request, user name, exception type, and stack trace")
    void serverErrorShowsIdAndLogsIt(CapturedOutput output) throws Exception {
        String page = errorPage(500, new IllegalStateException("internal details not shown to users"));
        var m = ID.matcher(page);
        assertThat(m.find()).as(page).isTrue();
        String id = m.group(1);
        assertThat(page).doesNotContain("IllegalStateException").doesNotContain("internal details not shown to users")
            .doesNotContain("at com.loandw");
        assertThat(output.getOut()).contains("ERROR")
            .contains("errorId=" + id + " GET /cases/42 user=analyst_demo java.lang.IllegalStateException")
            .contains("at com.loandw.review.ErrorPageWebTest");
    }

    @Test
    @DisplayName("403, 404, and 400 pages are unchanged and get no ID")
    void clientErrorsHaveNoId(CapturedOutput output) throws Exception {
        for (int code : new int[] {403, 404, 400}) {
            assertThat(errorPage(code, null)).doesNotContain("Error ID");
        }
        assertThat(output.getOut()).doesNotContain("errorId=");
    }
}
