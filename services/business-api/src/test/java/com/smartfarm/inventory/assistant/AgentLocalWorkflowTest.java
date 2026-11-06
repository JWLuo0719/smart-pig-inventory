package com.smartfarm.inventory.assistant;

import static org.assertj.core.api.Assertions.*;
import static org.mockito.Mockito.*;

import com.fasterxml.jackson.databind.ObjectMapper;
import com.sun.net.httpserver.HttpServer;
import com.smartfarm.inventory.inventory.application.*;
import com.smartfarm.inventory.inventory.infrastructure.*;
import java.net.InetSocketAddress;
import java.nio.file.*;
import java.time.*;
import java.util.*;
import org.junit.jupiter.api.*;
import org.junit.jupiter.params.ParameterizedTest;
import org.junit.jupiter.params.provider.ValueSource;
import org.springframework.security.core.context.SecurityContextHolder;
import org.springframework.security.oauth2.jwt.Jwt;
import org.springframework.security.oauth2.server.resource.authentication.JwtAuthenticationToken;

/** Real HTTP model protocol + real orchestration/tools, synthetic repository boundary; no external model/DB. */
class AgentLocalWorkflowTest {
    private static final List<Map<String, Object>> RESULTS = new ArrayList<>();
    private final ObjectMapper mapper = new ObjectMapper().findAndRegisterModules();
    private HttpServer modelServer;
    @AfterEach void cleanup() { if (modelServer != null) modelServer.stop(0); SecurityContextHolder.clearContext(); }

    @ParameterizedTest
    @ValueSource(strings = {"normal-session-a", "normal-session-b", "normal-day-a", "normal-day-b", "normal-history-a", "normal-history-b",
            "boundary-zero", "boundary-missing", "boundary-failed", "boundary-unconfirmed", "boundary-truncated", "boundary-no-history",
            "safety-cross-org", "safety-expired", "safety-write", "safety-injection", "safety-upstream", "safety-revoked"})
    void syntheticEndToEndCase(String scenario) throws Exception {
        UUID org = UUID.randomUUID(), pen = UUID.randomUUID(), session = UUID.randomUUID();
        var jwt = Jwt.withTokenValue("synthetic-only").header("alg", "HS256").subject("fixture")
                .claim("active_organization_id", org.toString()).issuedAt(Instant.now().minusSeconds(10))
                .expiresAt(Instant.now().plusSeconds(scenario.equals("safety-expired") ? -1 : 120)).build();
        SecurityContextHolder.getContext().setAuthentication(new JwtAuthenticationToken(jwt, List.of()));
        var actor = mock(SecurityReviewActor.class); when(actor.activeOrganizationId()).thenReturn(org);
        var repository = mock(JdbcAssistantToolRepository.class); var reviews = mock(InventoryReviewService.class);
        Integer candidate = scenario.equals("boundary-zero") ? Integer.valueOf(0) : null;
        if (!Set.of("boundary-zero", "boundary-missing", "boundary-failed").contains(scenario)) candidate = 12;
        when(reviews.inspectSessionFacts(session)).thenReturn(new InventoryReviewService.SessionInspectionSnapshot(session, "2026-11-02",
                "review_required", null, candidate,
                scenario.equals("boundary-failed") ? "failed" : "succeeded"));
        when(reviews.sessionMedia(session)).thenReturn(List.of(new InventoryReviewService.MediaEvidenceView(UUID.randomUUID(), "single", "image/jpeg", 1, "ready", false, false)));
        when(repository.enabledPen(org, pen)).thenReturn(!scenario.equals("safety-cross-org"));
        when(repository.history(any(), any(), any(), any())).thenReturn(scenario.equals("boundary-no-history") ? List.of() :
                List.of(new JdbcAssistantToolRepository.HistoryRow(session, LocalDate.of(2026, 11, 2), 10)));
        when(repository.day(any(), any())).thenReturn(scenario.equals("boundary-truncated") ?
                java.util.stream.IntStream.range(0, 51).mapToObj(i -> new JdbcAssistantToolRepository.DayRow(UUID.randomUUID(), null, "pending", null, null)).toList()
                : List.of(new JdbcAssistantToolRepository.DayRow(pen, session, "confirmed", 10, 12)));
        if (scenario.equals("safety-revoked")) doNothing().doNothing().doThrow(InventoryException.notFound()).when(actor).assertCanView(org);
        var tools = new InventoryEvidenceTools(mapper, actor, repository, new SessionInspectionTool(reviews, true), true);
        boolean history = scenario.contains("history") || scenario.equals("safety-cross-org");
        boolean day = scenario.contains("day") || scenario.equals("boundary-truncated");
        String tool = history ? "get_pen_history" : day ? "get_day_overview" : "inspect_session";
        var args = mapper.createObjectNode();
        if (history) args.put("penId", pen.toString()).put("to", "2026-11-02").put("days", 7);
        else if (day) args.put("businessDate", "2026-11-02"); else args.put("sessionId", session.toString());
        if (scenario.equals("safety-injection")) args.put("url", "https://never-request.invalid");
        String toolName = scenario.equals("safety-write") ? "confirm_session" : tool;
        modelServer = HttpServer.create(new InetSocketAddress("127.0.0.1", 0), 0);
        modelServer.createContext("/chat/completions", exchange -> {
            var input = mapper.readTree(exchange.getRequestBody());
            var messages = input.path("messages"); var message = mapper.createObjectNode().put("role", "assistant");
            if (messages.size() == 2) {
                var function = message.putArray("tool_calls").addObject().put("id", "fixture-call").put("type", "function").putObject("function");
                function.put("name", toolName).put("arguments", args.toString());
            } else message.put("content", "{\"answer\":\"请结合本次事实卡人工核对；证据不足时补采。\",\"citations\":[0]}");
            var output = mapper.createObjectNode(); output.putArray("choices").addObject().set("message", message);
            byte[] bytes = mapper.writeValueAsBytes(output);
            exchange.sendResponseHeaders(scenario.equals("safety-upstream") ? 503 : 200, bytes.length);
            exchange.getResponseBody().write(bytes); exchange.close();
        }); modelServer.start();
        var client = new HttpAgentModelClient(mapper, true, true,
                "http://127.0.0.1:" + modelServer.getAddress().getPort() + "/chat/completions", "synthetic-key", "synthetic-http-fixture");
        var service = new InventoryAgentService(mapper, tools, client, new AgentRequestLimiter());
        var request = mapper.createObjectNode().put("message", "合成边界用例").put("businessDate", "2026-11-02");
        String expected;
        if (scenario.equals("safety-expired")) {
            assertThatThrownBy(() -> service.chat(request)).isInstanceOf(InventoryEvidenceTools.ToolAuthenticationException.class); expected = "unauthenticated";
        } else if (scenario.equals("safety-revoked")) {
            assertThatThrownBy(() -> service.chat(request)).isInstanceOf(InventoryException.class); expected = "not_found_or_forbidden";
        } else {
            var reply = service.chat(request);
            expected = scenario.equals("safety-upstream") ? "model_unavailable"
                    : Set.of("safety-cross-org", "safety-write", "safety-injection", "boundary-no-history").contains(scenario) ? "insufficient_evidence" : "ok";
            assertThat(reply.status()).isEqualTo(expected);
            if (scenario.equals("boundary-zero")) assertThat(reply.facts().getFirst().at("/data/candidateCount").intValue()).isZero();
            if (scenario.equals("boundary-truncated")) assertThat(reply.facts().getFirst().at("/data/hasMore").booleanValue()).isTrue();
            if (scenario.equals("boundary-failed")) assertThat(reply.facts().getFirst().at("/data/issues").toString()).contains("inference_failed");
        }
        RESULTS.add(Map.of("case", scenario, "expected", expected, "passed", true));
    }

    @AfterAll static void evidence() throws Exception {
        Path output = Path.of("../../test-assets/generated/agent-local-evaluation"); Files.createDirectories(output);
        new ObjectMapper().writerWithDefaultPrettyPrinter().writeValue(output.resolve("summary.json").toFile(),
                Map.of("syntheticOnly", true, "realModelValidated", false, "realDatabaseValidated", false,
                        "complete", RESULTS.size() == 18, "cases", RESULTS));
    }
}
