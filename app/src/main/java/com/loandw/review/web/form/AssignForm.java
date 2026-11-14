package com.loandw.review.web.form;

import jakarta.validation.constraints.NotNull;
import jakarta.validation.constraints.Positive;

/** Form for a manager to assign a case. Whether the assignee is an analyst is checked by the service layer. */
public class AssignForm {

    @NotNull(message = "{form.assignee.required}")
    @Positive(message = "{form.assignee.format}")
    private Long assigneeUserId;

    public Long getAssigneeUserId() {
        return assigneeUserId;
    }

    public void setAssigneeUserId(Long assigneeUserId) {
        this.assigneeUserId = assigneeUserId;
    }
}
