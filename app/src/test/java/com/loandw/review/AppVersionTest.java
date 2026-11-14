package com.loandw.review;

import static org.assertj.core.api.Assertions.assertThat;

import java.util.Properties;

import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.support.StaticListableBeanFactory;
import org.springframework.boot.info.BuildProperties;

import com.loandw.review.config.AppVersion;

/** How the footer version is derived: short commit, -dirty for a dirty working tree, empty without build information. No database. */
class AppVersionTest {

    private static AppVersion version(String commit, String dirty) {
        StaticListableBeanFactory beans = new StaticListableBeanFactory();
        if (commit != null) {
            Properties p = new Properties();
            p.setProperty("version", "0.1.0");
            p.setProperty("commit", commit);
            p.setProperty("dirty", dirty);
            beans.addBean("buildProperties", new BuildProperties(p));
        }
        return new AppVersion(beans.getBeanProvider(BuildProperties.class));
    }

    @Test
    @DisplayName("A package built from a clean tree shows a 7-character commit; a dirty one adds -dirty")
    void shortCommit() {
        String commit = "0123456789abcdef0123456789abcdef01234567";
        assertThat(version(commit, "false").label()).isEqualTo("0123456");
        assertThat(version(commit, "true").label()).isEqualTo("0123456-dirty");
    }

    @Test
    @DisplayName("Without build information, or packaged without a commit (unknown), the footer shows no version")
    void missing() {
        assertThat(version(null, null).label()).isNull();
        assertThat(version("unknown", "unknown").label()).isNull();
    }
}
