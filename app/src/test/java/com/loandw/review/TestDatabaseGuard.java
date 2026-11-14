package com.loandw.review;

/** Write tests refuse to run unless the database marker says TEST. */
final class TestDatabaseGuard {
    private TestDatabaseGuard() { }

    static void check(java.sql.Connection connection) throws java.sql.SQLException {
        try (var statement = connection.createStatement();
             var result = statement.executeQuery("select environment_name from loan_dw.database_environment")) {
            if (!result.next() || !"TEST".equals(result.getString(1)) || result.next()) {
                connection.close();
                throw new java.sql.SQLException("Write tests require TEST database");
            }
        }
    }
}
