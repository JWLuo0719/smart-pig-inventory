package com.smartfarm.inventory.inventory.application;

import static org.assertj.core.api.Assertions.*;
import static org.mockito.Mockito.*;

import com.fasterxml.jackson.databind.ObjectMapper;
import com.fasterxml.jackson.databind.JsonNode;
import com.smartfarm.inventory.inventory.infrastructure.JdbcAssistantToolRepository;
import com.smartfarm.inventory.inventory.infrastructure.SecurityReviewActor;
import java.time.Instant;
import java.time.LocalDate;
import java.util.List;
import java.util.UUID;
import java.util.stream.IntStream;
import org.junit.jupiter.api.*;
import org.springframework.dao.DataAccessResourceFailureException;
import org.springframework.security.core.context.SecurityContextHolder;
import org.springframework.security.oauth2.jwt.Jwt;
import org.springframework.security.oauth2.server.resource.authentication.JwtAuthenticationToken;

class InventoryEvidenceToolsTest {
    private final ObjectMapper mapper = new ObjectMapper().findAndRegisterModules();
    private final UUID org = UUID.randomUUID(), pen = UUID.randomUUID(), session = UUID.randomUUID();
    private SecurityReviewActor actor; private JdbcAssistantToolRepository repository;
    private SessionInspectionTool inspection; private InventoryEvidenceTools tools;
    private final LocalDate date = LocalDate.of(2026, 11, 2);

    @BeforeEach void setup() {
        actor = mock(SecurityReviewActor.class); repository = mock(JdbcAssistantToolRepository.class);
        inspection = mock(SessionInspectionTool.class);
        tools = new InventoryEvidenceTools(mapper, actor, repository, inspection, true);
        when(actor.activeOrganizationId()).thenReturn(org);
        login(Instant.now().plusSeconds(60));
    }
    @AfterEach void clear() { SecurityContextHolder.clearContext(); }
    private void login(Instant expires) {
        var jwt = Jwt.withTokenValue("synthetic").header("alg", "HS256").subject("fixture")
                .claim("active_organization_id", org.toString()).issuedAt(Instant.now().minusSeconds(60)).expiresAt(expires).build();
        SecurityContextHolder.getContext().setAuthentication(new JwtAuthenticationToken(jwt, List.of()));
    }
    private JsonNode execute(String name, String args) throws Exception {
        return tools.execute(mapper.readTree("{\"tool\":\"" + name + "\",\"arguments\":" + args + "}"));
    }

    @Test void dayKeepsZeroUnknownAndCandidateDistinct() throws Exception {
        when(repository.day(org, date)).thenReturn(List.of(
                new JdbcAssistantToolRepository.DayRow(pen, session, "confirmed", 0, 5),
                new JdbcAssistantToolRepository.DayRow(UUID.randomUUID(), null, null, null, null)));
        var value = execute("get_day_overview", "{\"businessDate\":\"2026-11-02\"}");
        assertThat(value.at("/data/confirmedHeads").intValue()).isZero();
        assertThat(value.at("/data/confirmedPenCount").intValue()).isEqualTo(1);
        assertThat(value.at("/data/rows/1/confirmedCount").isNull()).isTrue();
        assertThat(value.at("/data/rows/0/candidateCount").intValue()).isEqualTo(5);
        assertThat(value.at("/evidence/0/id").isNull()).isTrue();
        verify(actor).assertCanView(org);
    }
    @Test void noConfirmedRecordsMeansUnknownTotalNotZero() throws Exception {
        when(repository.day(org, date)).thenReturn(List.of(new JdbcAssistantToolRepository.DayRow(pen, session, "review_required", null, 8)));
        assertThat(execute("get_day_overview", "{\"businessDate\":\"2026-11-02\"}").at("/data/confirmedHeads").isNull()).isTrue();
    }
    @Test void daySummaryUsesAllRowsAndMarksTruncation() throws Exception {
        when(repository.day(org, date)).thenReturn(IntStream.range(0, 51).mapToObj(i ->
                new JdbcAssistantToolRepository.DayRow(UUID.randomUUID(), UUID.randomUUID(), "confirmed", 2, 3)).toList());
        var value = execute("get_day_overview", "{\"businessDate\":\"2026-11-02\",\"limit\":2}");
        assertThat(value.at("/data/rows").size()).isEqualTo(2);
        assertThat(value.at("/data/hasMore").booleanValue()).isTrue();
        assertThat(value.at("/data/confirmedHeads").intValue()).isEqualTo(102);
    }
    @Test void historyUsesOnlyConfirmedRowsAndPreservesMissingDays() throws Exception {
        when(repository.enabledPen(org, pen)).thenReturn(true);
        when(repository.history(org, pen, date.minusDays(2), date)).thenReturn(List.of(
                new JdbcAssistantToolRepository.HistoryRow(session, date, 0)));
        var value = execute("get_pen_history", "{\"penId\":\"" + pen + "\",\"to\":\"2026-11-02\",\"days\":3}");
        assertThat(value.at("/data/points").size()).isEqualTo(3);
        assertThat(value.at("/data/points/0/confirmedCount").isNull()).isTrue();
        assertThat(value.at("/data/points/2/confirmedCount").intValue()).isZero();
        assertThat(value.at("/evidence/0/id").asText()).isEqualTo(session.toString());
    }
    @Test void crossOrganizationAndDisabledPenShareAnEmptyNotFoundResult() throws Exception {
        when(repository.enabledPen(org, pen)).thenReturn(false);
        var value = execute("get_pen_history", "{\"penId\":\"" + pen + "\",\"to\":\"2026-11-02\"}");
        assertThat(value.path("status").asText()).isEqualTo("not_found_or_forbidden");
        assertThat(value.path("data").isNull()).isTrue();
        verify(repository, never()).history(any(), any(), any(), any());
    }
    @Test void unknownZeroAndEmptyScopeAreNotInterchangeable() throws Exception {
        when(repository.day(org, date)).thenReturn(List.of());
        var value = execute("get_day_overview", "{\"businessDate\":\"2026-11-02\"}");
        assertThat(value.path("status").asText()).isEqualTo("ok");
        assertThat(value.at("/data/scopePenCount").intValue()).isZero();
        assertThat(value.at("/data/confirmedHeads").isNull()).isTrue();
    }
    @Test void membershipRevocationStopsAllRepositoryReads() throws Exception {
        doThrow(InventoryException.notFound()).when(actor).assertCanView(org);
        assertThat(execute("get_day_overview", "{\"businessDate\":\"2026-11-02\"}").path("status").asText()).isEqualTo("not_found_or_forbidden");
        verifyNoInteractions(repository);
    }
    @Test void missingExpiredOrDisabledAuthenticationCannotUseLocalDefaultOrganization() throws Exception {
        SecurityContextHolder.clearContext();
        assertThat(execute("get_day_overview", "{}").path("status").asText()).isEqualTo("unauthenticated");
        login(Instant.now().minusSeconds(1));
        assertThat(execute("get_day_overview", "{}").path("status").asText()).isEqualTo("unauthenticated");
        login(Instant.now().plusSeconds(60));
        var disabled = new InventoryEvidenceTools(mapper, actor, repository, inspection, false);
        assertThat(disabled.execute(mapper.createObjectNode()).path("status").asText()).isEqualTo("unauthenticated");
        verifyNoInteractions(repository);
    }
    @Test void invalidDateLimitAndExtraFieldsAreRejectedWithoutDatabaseReads() throws Exception {
        for (String args : List.of("{}", "{\"businessDate\":\"2026-02-30\"}",
                "{\"businessDate\":\"2026-11-02\",\"limit\":51}", "{\"businessDate\":\"2026-11-02\",\"limit\":1.0}",
                "{\"businessDate\":\"2026-11-02\",\"org\":\"other\"}", "{\"businessDate\":\"2026-11-02\",\"url\":\"https://bad\"}")) {
            assertThat(execute("get_day_overview", args).path("status").asText()).isEqualTo("invalid_arguments");
        }
        verifyNoInteractions(repository);
    }
    @Test void invalidHistoryWindowAndShortUuidAreRejected() throws Exception {
        for (String args : List.of("{\"penId\":\"1-1-1-1-1\",\"to\":\"2026-11-02\"}",
                "{\"penId\":\"" + pen + "\",\"to\":\"2026-11-02\",\"days\":91}")) {
            assertThat(execute("get_pen_history", args).path("status").asText()).isEqualTo("invalid_arguments");
        }
        verifyNoInteractions(repository);
    }
    @Test void databaseFailureReturnsUnknownNotFakeZeroOrErrorDetail() throws Exception {
        when(repository.day(org, date)).thenThrow(new DataAccessResourceFailureException("private detail"));
        var value = execute("get_day_overview", "{\"businessDate\":\"2026-11-02\"}");
        assertThat(value.path("status").asText()).isEqualTo("unavailable");
        assertThat(value.toString()).doesNotContain("private detail");
    }
    @Test void writeToolAndRootExtrasAreRejected() throws Exception {
        assertThat(execute("confirm_session", "{}").path("status").asText()).isEqualTo("invalid_arguments");
        assertThat(tools.execute(mapper.readTree("{\"tool\":\"get_day_overview\",\"arguments\":{},\"token\":\"secret\"}"))
                .path("status").asText()).isEqualTo("invalid_arguments");
        verifyNoInteractions(repository);
    }
}
