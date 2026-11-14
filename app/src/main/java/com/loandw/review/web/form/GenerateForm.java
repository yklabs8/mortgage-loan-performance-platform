package com.loandw.review.web.form;

import java.time.YearMonth;

import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.NotNull;
import jakarta.validation.constraints.Pattern;

/** Form to select candidates: which release, which month, which rule. */
public class GenerateForm {

    /** A release ID may contain only uppercase letters, digits, and underscores, at most 10 characters (review_candidate.source_release_id is varchar2(10)). */
    @NotBlank(message = "{form.release.required}")
    @Pattern(regexp = "[A-Z0-9_]{1,10}", message = "{form.release.format}")
    private String releaseId;

    /** The month input sends values such as 2020-06. */
    @NotNull(message = "{form.month.required}")
    private YearMonth month;

    /** Rule code at most 30 characters (review_rule.rule_code is varchar2(30)). */
    @NotBlank(message = "{form.rule.required}")
    @Pattern(regexp = "[A-Z0-9_]{1,30}", message = "{form.rule.format}")
    private String ruleCode;

    public String getReleaseId() {
        return releaseId;
    }

    public void setReleaseId(String releaseId) {
        this.releaseId = releaseId;
    }

    public YearMonth getMonth() {
        return month;
    }

    public void setMonth(YearMonth month) {
        this.month = month;
    }

    public String getRuleCode() {
        return ruleCode;
    }

    public void setRuleCode(String ruleCode) {
        this.ruleCode = ruleCode;
    }
}
