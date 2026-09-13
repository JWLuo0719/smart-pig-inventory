package com.smartfarm.inventory.observability;

import io.micrometer.core.instrument.Gauge;
import io.micrometer.core.instrument.MeterRegistry;
import java.time.Instant;
import java.util.ArrayList;
import java.util.List;
import java.util.Map;
import org.springframework.scheduling.annotation.Scheduled;
import org.springframework.stereotype.Component;

@Component
public class BusinessMetrics {
    private final BusinessMetricsSnapshotRepository repository;
    private volatile Map<String, Double> snapshot = Map.of();
    private volatile double lastSuccess;
    private volatile double available;

    public BusinessMetrics(BusinessMetricsSnapshotRepository repository, MeterRegistry registry) {
        this.repository = repository;
        List<String> names = new ArrayList<>(List.of("pig.inventory.review.pending", "pig.inference.jobs.outstanding",
                "pig.inference.outbox.pending", "pig.inference.outbox.oldest.seconds", "pig.inference.retries.last24h",
                "pig.inventory.review.completed.last24h"));
        for (String status : List.of("succeeded", "review_required", "failed")) {
            names.add("pig.inference.results." + status + ".last24h");
            names.add("pig.inference.latency." + status + ".samples.last24h");
            names.add("pig.inference.latency." + status + ".seconds.last24h");
        }
        names.forEach(name -> Gauge.builder(name, this, source -> source.snapshot.getOrDefault(name, Double.NaN))
                .description("Database snapshot; last24h names are rolling gauges, never apply rate()").register(registry));
        Gauge.builder("pig.metrics.snapshot.available", this, source -> source.available).register(registry);
        Gauge.builder("pig.metrics.snapshot.last.success.timestamp.seconds", this, source -> source.lastSuccess).register(registry);
    }

    @Scheduled(scheduler = "businessMetricsScheduler", fixedDelayString = "${app.monitoring.snapshot-delay-ms:30000}", initialDelayString = "${app.monitoring.snapshot-delay-ms:30000}")
    public void refresh() {
        try {
            snapshot = repository.read();
            lastSuccess = Instant.now().getEpochSecond();
            available = 1;
        } catch (RuntimeException failure) {
            // Do not expose SQL/credentials or represent a failed read as an empty queue.
            snapshot = Map.of();
            available = 0;
        }
    }
}
