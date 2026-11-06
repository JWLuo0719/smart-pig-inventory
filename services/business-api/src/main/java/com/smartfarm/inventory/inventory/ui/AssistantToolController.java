package com.smartfarm.inventory.inventory.ui;

import com.fasterxml.jackson.databind.JsonNode;
import com.smartfarm.inventory.inventory.application.SessionInspectionTool;
import com.smartfarm.inventory.inventory.application.InventoryEvidenceTools;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RestController;

@RestController
public class AssistantToolController {
    private final SessionInspectionTool tool;
    private final InventoryEvidenceTools tools;

    public AssistantToolController(SessionInspectionTool tool, InventoryEvidenceTools tools) {
        this.tool = tool; this.tools = tools;
    }

    @PostMapping("/api/v1/assistant/tools/inspect-session")
    ResponseEntity<SessionInspectionTool.Result> inspect(@RequestBody JsonNode request) {
        var result = tool.execute(request);
        int status = switch (result.status()) {
            case "unauthenticated" -> 401;
            case "not_found_or_forbidden" -> 404;
            case "invalid_arguments" -> 422;
            case "unavailable" -> 503;
            default -> 200;
        };
        return ResponseEntity.status(status).header("Cache-Control", "no-store").body(result);
    }

    @PostMapping({"/api/v1/assistant/tools/get-day-overview", "/api/v1/assistant/tools/get-pen-history"})
    ResponseEntity<JsonNode> read(@RequestBody JsonNode request, jakarta.servlet.http.HttpServletRequest servlet) {
        String expected = servlet.getRequestURI().endsWith("get-day-overview") ? "get_day_overview" : "get_pen_history";
        if (request == null || !request.isObject() || !expected.equals(request.path("tool").asText())) {
            var invalid = com.fasterxml.jackson.databind.node.JsonNodeFactory.instance.objectNode().put("tool", expected);
            invalid.putObject("arguments").putNull("invalid_request"); request = invalid;
        }
        JsonNode result = tools.execute(request);
        int status = switch (result.path("status").asText()) {
            case "unauthenticated" -> 401;
            case "not_found_or_forbidden" -> 404;
            case "invalid_arguments" -> 422;
            case "unavailable" -> 503;
            default -> 200;
        };
        return ResponseEntity.status(status).header("Cache-Control", "no-store").body(result);
    }
}
