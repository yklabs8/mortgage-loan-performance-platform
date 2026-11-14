package com.loandw.review;

import org.springframework.boot.SpringApplication;
import org.springframework.boot.autoconfigure.SpringBootApplication;

/**
 * Loan risk review web application: analysts view candidates, open cases, and write notes; managers assign, close, or escalate.
 * Review business rules and transactions are in the Java service layer; the database keeps constraints and audit triggers, and review_api keeps only the candidate reference interface.
 */
@SpringBootApplication
public class ReviewApplication {

    public static void main(String[] args) {
        SpringApplication.run(ReviewApplication.class, args);
    }
}
