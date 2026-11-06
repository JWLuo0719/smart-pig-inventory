package com.smartfarm.inventory.assistant;

import com.fasterxml.jackson.databind.JsonNode;
import com.smartfarm.inventory.inventory.application.InventoryEvidenceTools;
import com.smartfarm.inventory.inventory.application.InventoryException;
import java.util.Map;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.*;

@RestController
@RequestMapping("/api/v1/assistant")
public class InventoryAgentController {
    private final InventoryAgentService service;
    public InventoryAgentController(InventoryAgentService service) { this.service = service; }
    @GetMapping("/status") public ResponseEntity<JsonNode> status() {
        return ResponseEntity.ok().header("Cache-Control", "no-store").body(service.status());
    }
    @PostMapping("/chat") public ResponseEntity<InventoryAgentService.Reply> chat(@RequestBody JsonNode request) {
        return ResponseEntity.ok().header("Cache-Control", "no-store").body(service.chat(request));
    }

    @RestControllerAdvice(assignableTypes = InventoryAgentController.class)
    public static class Problems {
        @ExceptionHandler(InventoryEvidenceTools.ToolAuthenticationException.class)
        ResponseEntity<Map<String, String>> unauthenticated() { return problem(401, "ASSISTANT_UNAUTHENTICATED", "请重新登录后使用盘点助手。"); }
        @ExceptionHandler(InventoryException.class)
        ResponseEntity<Map<String, String>> forbidden() { return problem(404, "ASSISTANT_NOT_AVAILABLE", "当前组织的盘点助手不可用。"); }
        @ExceptionHandler({InventoryAgentService.InvalidRequestException.class, org.springframework.http.converter.HttpMessageNotReadableException.class})
        ResponseEntity<Map<String, String>> invalid() { return problem(422, "ASSISTANT_INVALID_REQUEST", "请检查问题、业务日期和所选记录。"); }
        @ExceptionHandler(InventoryAgentService.DisabledException.class)
        ResponseEntity<Map<String, String>> disabled() { return problem(503, "ASSISTANT_NOT_CONFIGURED", "智能问答尚未启用，请联系服务负责人完成模型配置。"); }
        @ExceptionHandler(AgentRequestLimiter.LimitException.class)
        ResponseEntity<Map<String, String>> limited() { return problem(429, "ASSISTANT_RATE_LIMIT", "当前请求较多，请稍后重试。"); }
        private ResponseEntity<Map<String, String>> problem(int status, String code, String message) {
            return ResponseEntity.status(status).header("Cache-Control", "no-store").body(Map.of("code", code, "message", message));
        }
    }
}
