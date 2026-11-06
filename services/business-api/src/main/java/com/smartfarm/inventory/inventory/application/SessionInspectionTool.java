package com.smartfarm.inventory.inventory.application;

import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.annotation.JsonInclude;
import java.time.Instant;
import java.util.ArrayList;
import java.util.List;
import java.util.Set;
import java.util.UUID;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.dao.DataAccessException;
import org.springframework.security.core.context.SecurityContextHolder;
import org.springframework.security.oauth2.server.resource.authentication.JwtAuthenticationToken;
import org.springframework.stereotype.Service;

/** Minimal read-only projection. The existing review service remains the authorization authority. */
@Service
public class SessionInspectionTool {
    private static final Set<String> STATES = Set.of("pending", "submitted", "processing", "review_required",
            "confirmed", "superseded");
    private final InventoryReviewService reviews;
    private final boolean securityEnabled;

    public SessionInspectionTool(InventoryReviewService reviews,
            @Value("${app.security.enabled:true}") boolean securityEnabled) {
        this.reviews = reviews;
        this.securityEnabled = securityEnabled;
    }

    public Result execute(JsonNode request) {
        var authentication = SecurityContextHolder.getContext().getAuthentication();
        if (!securityEnabled || !(authentication instanceof JwtAuthenticationToken jwt) || !jwt.isAuthenticated()
                || (jwt.getToken().getExpiresAt() != null && !jwt.getToken().getExpiresAt().isAfter(Instant.now()))) {
            return error("unauthenticated");
        }
        UUID sessionId = parseSessionId(request);
        if (sessionId == null) return error("invalid_arguments");
        try {
            // Both reads independently enforce the signed organization and current membership.
            var session = reviews.inspectSessionFacts(sessionId);
            var media = reviews.sessionMedia(sessionId);
            String state = STATES.contains(session.status() == null ? "" : session.status())
                    ? session.status() : "unknown";
            List<String> issues = new ArrayList<>();
            if ("review_required".equals(state)) issues.add("review_required");
            if ("failed".equals(session.inferenceStatus())) issues.add("inference_failed");
            if (media.stream().noneMatch(item -> !item.deleted())) issues.add("missing_evidence");
            if ("unknown".equals(state)) issues.add("unknown");
            Integer confirmed = Set.of("confirmed", "superseded").contains(state) ? session.confirmedCount() : null;
            var data = new Facts(session.id(), state, confirmed, session.candidateCount(), List.copyOf(issues));
            return new Result("1.0", "inspect_session", "ok", Instant.now(), data,
                    List.of(new Evidence("session", session.id(), session.businessDate())));
        } catch (InventoryException exception) {
            if (exception.status() == 404) return error("not_found_or_forbidden");
            throw exception;
        } catch (DataAccessException exception) {
            return error("unavailable");
        }
    }

    private UUID parseSessionId(JsonNode request) {
        if (request == null || !request.isObject() || request.size() != 2
                || !"inspect_session".equals(request.path("tool").asText())) return null;
        JsonNode arguments = request.path("arguments");
        if (!arguments.isObject() || arguments.size() != 1 || !arguments.path("sessionId").isTextual()) return null;
        String value = arguments.path("sessionId").textValue();
        try {
            UUID id = UUID.fromString(value);
            return id.toString().equalsIgnoreCase(value) ? id : null;
        } catch (IllegalArgumentException exception) {
            return null;
        }
    }

    private Result error(String status) {
        return new Result("1.0", "inspect_session", status, Instant.now(), null, List.of());
    }

    @JsonInclude(JsonInclude.Include.ALWAYS)
    public record Result(String schemaVersion, String tool, String status,
            @com.fasterxml.jackson.annotation.JsonFormat(shape = com.fasterxml.jackson.annotation.JsonFormat.Shape.STRING) Instant generatedAt,
            Facts data, List<Evidence> evidence) {}
    @JsonInclude(JsonInclude.Include.ALWAYS)
    public record Facts(UUID sessionId, String state, Integer confirmedCount, Integer candidateCount,
            List<String> issues) {}
    public record Evidence(String kind, UUID id, String businessDate) {}
}
