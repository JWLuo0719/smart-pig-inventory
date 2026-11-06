package com.smartfarm.inventory.inventory.application;

import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;
import com.fasterxml.jackson.databind.node.ObjectNode;
import com.smartfarm.inventory.inventory.infrastructure.JdbcAssistantToolRepository;
import com.smartfarm.inventory.inventory.infrastructure.SecurityReviewActor;
import java.time.Instant;
import java.time.LocalDate;
import java.util.HashMap;
import java.util.Iterator;
import java.util.Map;
import java.util.Set;
import java.util.UUID;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.dao.DataAccessException;
import org.springframework.security.core.context.SecurityContextHolder;
import org.springframework.security.oauth2.server.resource.authentication.JwtAuthenticationToken;
import org.springframework.stereotype.Service;

@Service
public class InventoryEvidenceTools {
    private static final Set<String> STATES = Set.of("pending", "submitted", "processing", "review_required", "confirmed", "superseded");
    private final ObjectMapper mapper;
    private final SecurityReviewActor actor;
    private final JdbcAssistantToolRepository repository;
    private final SessionInspectionTool inspection;
    private final boolean securityEnabled;

    public InventoryEvidenceTools(ObjectMapper mapper, SecurityReviewActor actor, JdbcAssistantToolRepository repository,
            SessionInspectionTool inspection, @Value("${app.security.enabled:true}") boolean securityEnabled) {
        this.mapper = mapper; this.actor = actor; this.repository = repository;
        this.inspection = inspection; this.securityEnabled = securityEnabled;
    }

    public void requireIdentity() {
        var auth = SecurityContextHolder.getContext().getAuthentication();
        if (!securityEnabled || !(auth instanceof JwtAuthenticationToken jwt) || !jwt.isAuthenticated()
                || (jwt.getToken().getExpiresAt() != null && !jwt.getToken().getExpiresAt().isAfter(Instant.now()))) {
            throw new ToolAuthenticationException();
        }
        actor.assertCanView(actor.activeOrganizationId());
    }

    public JsonNode execute(JsonNode request) {
        String tool = request != null && request.path("tool").isTextual() ? request.path("tool").textValue() : "unknown";
        try {
            requireIdentity();
            if (!fields(request, Set.of("tool", "arguments"), Set.of("tool", "arguments"))) return error(tool, "invalid_arguments");
            JsonNode args = request.get("arguments");
            if ("inspect_session".equals(tool)) return mapper.valueToTree(inspection.execute(request));
            UUID org = actor.activeOrganizationId();
            return switch (tool) {
                case "get_day_overview" -> day(org, args);
                case "get_pen_history" -> history(org, args);
                default -> error(tool, "invalid_arguments");
            };
        } catch (ToolAuthenticationException exception) { return error(tool, "unauthenticated");
        } catch (InventoryException exception) {
            if (exception.status() == 404) return error(tool, "not_found_or_forbidden");
            throw exception;
        } catch (IllegalArgumentException | java.time.DateTimeException exception) {
            return error(tool, "invalid_arguments");
        } catch (DataAccessException exception) { return error(tool, "unavailable"); }
    }

    private JsonNode day(UUID org, JsonNode args) {
        if (!fields(args, Set.of("businessDate", "limit"), Set.of("businessDate"))) return error("get_day_overview", "invalid_arguments");
        LocalDate date = date(args, "businessDate");
        int limit = integer(args, "limit", 20, 50);
        var rows = repository.day(org, date);
        ObjectNode result = envelope("get_day_overview", "ok");
        ObjectNode data = result.putObject("data");
        var confirmed = rows.stream().filter(row -> "confirmed".equals(row.state()) && row.confirmed() != null).toList();
        data.put("scopePenCount", rows.size()).put("confirmedPenCount", confirmed.size());
        if (confirmed.isEmpty()) data.putNull("confirmedHeads");
        else data.put("confirmedHeads", confirmed.stream().mapToLong(row -> row.confirmed()).sum());
        data.put("hasMore", rows.size() > limit);
        var items = data.putArray("rows");
        for (var row : rows.stream().limit(limit).toList()) {
            var item = items.addObject().put("penId", row.penId().toString());
            if (row.sessionId() == null) item.putNull("sessionId"); else item.put("sessionId", row.sessionId().toString());
            item.put("state", row.state() == null ? "pending" : STATES.contains(row.state()) ? row.state() : "unknown");
            item.set("confirmedCount", mapper.valueToTree("confirmed".equals(row.state()) ? row.confirmed() : null));
            item.set("candidateCount", mapper.valueToTree(row.candidate()));
        }
        result.withArray("evidence").addObject().put("kind", "daily_report").putNull("id").put("businessDate", date.toString());
        return result;
    }

    private JsonNode history(UUID org, JsonNode args) {
        if (!fields(args, Set.of("penId", "to", "days"), Set.of("penId", "to"))) return error("get_pen_history", "invalid_arguments");
        UUID pen = uuid(args, "penId"); LocalDate to = date(args, "to");
        int days = integer(args, "days", 7, 90); LocalDate from = to.minusDays(days - 1L);
        if (!repository.enabledPen(org, pen)) return error("get_pen_history", "not_found_or_forbidden");
        var rows = repository.history(org, pen, from, to);
        Map<LocalDate, Integer> counts = new HashMap<>();
        for (var row : rows) {
            if (counts.containsKey(row.date())) return error("get_pen_history", "unavailable");
            counts.put(row.date(), row.confirmed());
        }
        ObjectNode result = envelope("get_pen_history", "ok");
        ObjectNode data = result.putObject("data").put("penId", pen.toString()).put("scopeBasis", "current_enabled_pens");
        var points = data.putArray("points");
        for (LocalDate day = from; !day.isAfter(to); day = day.plusDays(1)) {
            points.addObject().put("date", day.toString()).set("confirmedCount", mapper.valueToTree(counts.get(day)));
        }
        for (var row : rows.stream().limit(50).toList()) {
            result.withArray("evidence").addObject().put("kind", "session")
                    .put("id", row.sessionId().toString()).put("businessDate", row.date().toString());
        }
        return result;
    }

    private ObjectNode envelope(String tool, String status) {
        ObjectNode result = mapper.createObjectNode().put("schemaVersion", "1.0").put("tool", tool)
                .put("status", status).put("generatedAt", Instant.now().toString());
        result.putNull("data"); result.putArray("evidence"); return result;
    }
    private JsonNode error(String tool, String status) { return envelope(tool, status); }

    public static boolean fields(JsonNode value, Set<String> allowed, Set<String> required) {
        if (value == null || !value.isObject()) return false;
        for (String key : required) if (!value.has(key)) return false;
        Iterator<String> names = value.fieldNames();
        while (names.hasNext()) if (!allowed.contains(names.next())) return false;
        return true;
    }
    public static UUID uuid(JsonNode value, String key) {
        String raw = text(value, key); UUID id = UUID.fromString(raw);
        if (!id.toString().equalsIgnoreCase(raw)) throw new IllegalArgumentException();
        return id;
    }
    public static LocalDate date(JsonNode value, String key) {
        String raw = text(value, key); LocalDate date = LocalDate.parse(raw);
        if (raw.length() != 10 || !date.toString().equals(raw)) throw new IllegalArgumentException();
        return date;
    }
    public static String text(JsonNode value, String key) {
        if (!value.path(key).isTextual()) throw new IllegalArgumentException();
        return value.path(key).textValue();
    }
    private int integer(JsonNode value, String key, int fallback, int maximum) {
        if (!value.has(key)) return fallback;
        JsonNode item = value.get(key);
        if (!item.isIntegralNumber() || !item.canConvertToInt() || item.intValue() < 1 || item.intValue() > maximum) throw new IllegalArgumentException();
        return item.intValue();
    }
    public static class ToolAuthenticationException extends RuntimeException {}
}
