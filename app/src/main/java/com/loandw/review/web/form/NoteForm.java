package com.loandw.review.web.form;

import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.Size;

/** Form for writing a note. */
public class NoteForm {

    /**
     * Maximum characters for notes and reasons. The database columns note_text and decision_note are varchar2(4000), counted in bytes;
     * in UTF-8 a CJK character takes 3 bytes and an emoji 4, so the limit is 1000 characters, which always fits (without a limit an overlong note would become a database error).
     */
    public static final int MAX_CHARS = 1000;

    @NotBlank(message = "{form.note.required}")
    @Size(max = MAX_CHARS, message = "{form.note.tooLong}")
    private String noteText;

    public String getNoteText() {
        return noteText;
    }

    public void setNoteText(String noteText) {
        this.noteText = noteText;
    }
}
