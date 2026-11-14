package com.loandw.review.web.form;

import jakarta.validation.constraints.AssertTrue;
import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.Pattern;

/**
 * Password change form. New password rules: 12-64 visible ASCII characters (no spaces), at least one letter and one digit.
 * ASCII only: BCrypt uses only the first 72 bytes, and non-ASCII characters take several bytes, so ASCII guarantees all 64 characters count in the hash.
 */
public class PasswordForm {

    @NotBlank(message = "{form.password.oldRequired}")
    private String oldPassword;

    @Pattern(regexp = "(?=.*[A-Za-z])(?=.*[0-9])[\\x21-\\x7E]{12,64}",
        message = "{form.password.rule}")
    @NotBlank(message = "{form.password.newRequired}")
    private String newPassword;

    private String confirmPassword;

    @AssertTrue(message = "{form.password.mismatch}")
    public boolean isConfirmed() {
        return newPassword == null || newPassword.equals(confirmPassword);
    }

    public String getOldPassword() {
        return oldPassword;
    }

    public void setOldPassword(String oldPassword) {
        this.oldPassword = oldPassword;
    }

    public String getNewPassword() {
        return newPassword;
    }

    public void setNewPassword(String newPassword) {
        this.newPassword = newPassword;
    }

    public String getConfirmPassword() {
        return confirmPassword;
    }

    public void setConfirmPassword(String confirmPassword) {
        this.confirmPassword = confirmPassword;
    }
}
