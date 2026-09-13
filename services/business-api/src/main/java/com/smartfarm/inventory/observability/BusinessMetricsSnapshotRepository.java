package com.smartfarm.inventory.observability;

import java.util.LinkedHashMap;
import java.util.Map;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.stereotype.Repository;
import org.springframework.transaction.annotation.Isolation;
import org.springframework.transaction.annotation.Transactional;

@Repository
public class BusinessMetricsSnapshotRepository {
    private final JdbcTemplate jdbc;

    public BusinessMetricsSnapshotRepository(JdbcTemplate jdbc) { this.jdbc = jdbc; }

    /** One read-only database snapshot; rolling windows are gauges, NOT process counters. */
    @Transactional(readOnly = true, isolation = Isolation.REPEATABLE_READ, timeout = 5)
    public Map<String, Double> read() {
        Map<String, Double> values = new LinkedHashMap<>();
        values.put("pig.inventory.review.pending", scalar("SELECT COUNT(*) FROM inventory_session WHERE status = 'review_required'"));
        values.put("pig.inference.jobs.outstanding", scalar("SELECT COUNT(*) FROM inference_job WHERE status IN ('submitted','processing')"));
        values.put("pig.inference.outbox.pending", scalar("SELECT COUNT(*) FROM domain_event_outbox WHERE state IN ('PENDING','DISPATCHING') AND event_type IN ('capture_package.committed.v1','inference_job.retry_requested.v1')"));
        values.put("pig.inference.outbox.oldest.seconds", scalar("SELECT COALESCE(MAX(TIMESTAMPDIFF(SECOND, created_at, CURRENT_TIMESTAMP)),0) FROM domain_event_outbox WHERE state IN ('PENDING','DISPATCHING') AND event_type IN ('capture_package.committed.v1','inference_job.retry_requested.v1')"));
        values.put("pig.inference.retries.last24h", scalar("SELECT COUNT(*) FROM inference_job WHERE retry_requested_at >= CURRENT_TIMESTAMP - INTERVAL 24 HOUR"));
        // Review completion counts original evidence sessions only; corrections do not inflate it.
        values.put("pig.inventory.review.completed.last24h", scalar("SELECT COUNT(*) FROM inventory_session WHERE confirmed_at >= CURRENT_TIMESTAMP - INTERVAL 24 HOUR AND supersedes_session_id IS NULL AND status IN ('confirmed','superseded')"));
        for (String status : new String[] {"succeeded", "review_required", "failed"}) {
            var row = jdbc.queryForMap("""
                    SELECT /*+ MAX_EXECUTION_TIME(3000) */ COUNT(*) AS results,
                      COUNT(r.latency_ms) AS samples, COALESCE(SUM(r.latency_ms),0)/1000.0 AS seconds
                    FROM inference_job j JOIN count_result r ON r.inference_job_id = j.id
                    WHERE j.status = ? AND j.finished_at >= CURRENT_TIMESTAMP - INTERVAL 24 HOUR
                    """, status);
            values.put("pig.inference.results." + status + ".last24h", ((Number) row.get("results")).doubleValue());
            values.put("pig.inference.latency." + status + ".samples.last24h", ((Number) row.get("samples")).doubleValue());
            values.put("pig.inference.latency." + status + ".seconds.last24h", ((Number) row.get("seconds")).doubleValue());
        }
        return Map.copyOf(values);
    }

    private double scalar(String sql) {
        return jdbc.queryForObject(sql.replaceFirst("SELECT", "SELECT /*+ MAX_EXECUTION_TIME(3000) */"), Double.class);
    }
}
