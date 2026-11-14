package com.loandw.review.web.form;

import jakarta.validation.constraints.AssertTrue;
import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.NotNull;
import jakarta.validation.constraints.Pattern;
import jakarta.validation.constraints.Size;

/**
 * Form for a manager's decision (close, escalate, or reopen). Critical operations run only when "I confirm" is ticked.
 * The confirmation is checked on the server: a confirmation dialog only on the web page would be skipped by a request that bypasses the page.
 */
public class DecisionForm {

    /** Matches the database check constraint review_decision_type_ck. */
    @NotBlank(message = "{form.decision.required}")
    @Pattern(regexp = "CLOSE|ESCALATE|REOPEN", message = "{form.decision.format}")
    private String decisionType;

    @NotBlank(message = "{error.case.stale}")
    @Size(max = 20, message = "{form.expectedStatus.format}")
    private String expectedStatus;

    public String getExpectedStatus() {
        return expectedStatus;
    }

    public void setExpectedStatus(String expectedStatus) {
        this.expectedStatus = expectedStatus;
    }

    @NotBlank(message = "{form.reason.required}")
    @Size(max = NoteForm.MAX_CHARS, message = "{form.reason.tooLong}")
    private String decisionNote;

    /** An unticked box sends no field, so the value is null; @AssertTrue accepts null, so @NotNull is needed too. */
    @NotNull(message = "{form.confirm.required}")
    @AssertTrue(message = "{form.confirm.required}")
    private Boolean confirmed;

    public String getDecisionType() {
        return decisionType;
    }

    public void setDecisionType(String decisionType) {
        this.decisionType = decisionType;
    }

    public String getDecisionNote() {
        return decisionNote;
    }

    public void setDecisionNote(String decisionNote) {
        this.decisionNote = decisionNote;
    }

    public Boolean getConfirmed() {
        return confirmed;
    }

    public void setConfirmed(Boolean confirmed) {
        this.confirmed = confirmed;
    }
}
