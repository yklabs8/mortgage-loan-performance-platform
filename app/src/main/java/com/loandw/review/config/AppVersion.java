package com.loandw.review.config;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.beans.factory.ObjectProvider;
import org.springframework.boot.context.event.ApplicationReadyEvent;
import org.springframework.boot.info.BuildProperties;
import org.springframework.context.event.EventListener;
import org.springframework.stereotype.Component;

/**
 * Which code version is running: the commit and clean/dirty working tree written into META-INF/build-info.properties at packaging (passed by scripts/12_run_app.sh).
 * Logs one version line at startup and shows the short commit in the footer; without build information (for example running in an IDE) the footer omits it and pages work as usual.
 */
@Component
public class AppVersion {

    private static final Logger log = LoggerFactory.getLogger(AppVersion.class);

    private final String label;
    private final String detail;

    public AppVersion(ObjectProvider<BuildProperties> build) {
        BuildProperties props = build.getIfAvailable();
        this.label = label(props);
        this.detail = props == null ? "no build information"
            : "version=" + props.getVersion() + " commit=" + props.get("commit") + " dirty=" + props.get("dirty")
                + " built=" + props.getTime();
    }

    /** Short commit (first 7 characters), with -dirty for a dirty working tree; null when build information or the commit is unavailable. */
    static String label(BuildProperties props) {
        if (props == null) return null;
        String commit = props.get("commit");
        if (commit == null || !commit.matches("[0-9a-f]{7,40}")) return null;
        return commit.substring(0, 7) + ("false".equals(props.get("dirty")) ? "" : "-dirty");
    }

    public String label() {
        return label;
    }

    @EventListener(ApplicationReadyEvent.class)
    public void logVersion() {
        log.info("Web application version {}", detail);
    }
}
