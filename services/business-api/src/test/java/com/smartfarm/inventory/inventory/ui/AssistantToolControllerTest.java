package com.smartfarm.inventory.inventory.ui;

import static org.mockito.Mockito.*;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.post;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.*;

import com.smartfarm.inventory.inventory.application.InventoryException;
import com.smartfarm.inventory.inventory.application.InventoryReviewService;
import com.smartfarm.inventory.inventory.application.SessionInspectionTool;
import java.util.List;
import java.util.UUID;
import org.junit.jupiter.api.AfterEach;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.springframework.dao.DataAccessResourceFailureException;
import org.springframework.http.MediaType;
import org.springframework.security.core.context.SecurityContextHolder;
import org.springframework.security.oauth2.jwt.Jwt;
import org.springframework.security.oauth2.server.resource.authentication.JwtAuthenticationToken;
import org.springframework.test.web.servlet.MockMvc;
import org.springframework.test.web.servlet.setup.MockMvcBuilders;

class AssistantToolControllerTest {
    private final UUID id = UUID.randomUUID();
    private InventoryReviewService reviews;
    private MockMvc mvc;

    @BeforeEach
    void setUp() {
        reviews = mock(InventoryReviewService.class);
        mvc = controller(true);
        SecurityContextHolder.clearContext();
        login();
    }

    @AfterEach
    void clear() { SecurityContextHolder.clearContext(); }

    @Test
    void zeroCandidateIsNotAConfirmedCountAndDoesNotExposeInternalFields() throws Exception {
        facts("review_required", 0, null, "succeeded");
        submit(request()).andExpect(status().isOk())
                .andExpect(header().string("Cache-Control", "no-store"))
                .andExpect(jsonPath("$.data.candidateCount").value(0))
                .andExpect(jsonPath("$.data.confirmedCount").isEmpty())
                .andExpect(jsonPath("$.data.issues[0]").value("review_required"))
                .andExpect(jsonPath("$.evidence[0].id").value(id.toString()))
                .andExpect(jsonPath("$.data.model").doesNotExist())
                .andExpect(jsonPath("$.data.failureMessage").doesNotExist());
        verify(reviews).inspectSessionFacts(id);
        verify(reviews).sessionMedia(id);
        verifyNoMoreInteractions(reviews);
    }

    @Test
    void confirmedAndHistoricalCountsStaySeparateFromCandidate() throws Exception {
        for (String state : List.of("confirmed", "superseded")) {
            facts(state, 12, 10, "succeeded");
            submit(request()).andExpect(status().isOk())
                    .andExpect(jsonPath("$.data.confirmedCount").value(10))
                    .andExpect(jsonPath("$.data.candidateCount").value(12));
        }
    }

    @Test
    void missingConfirmedQuantityNeverFallsBackToCandidate() throws Exception {
        facts("confirmed", 12, null, "succeeded");
        submit(request()).andExpect(jsonPath("$.data.confirmedCount").isEmpty());
    }

    @Test
    void failureKeepsQuantityUnknownAndOnlyReturnsControlledIssues() throws Exception {
        facts("review_required", null, null, "failed");
        when(reviews.sessionMedia(id)).thenReturn(List.of());
        submit(request()).andExpect(status().isOk())
                .andExpect(jsonPath("$.data.candidateCount").isEmpty())
                .andExpect(jsonPath("$.data.issues[1]").value("inference_failed"))
                .andExpect(jsonPath("$.data.issues[2]").value("missing_evidence"));
    }

    @Test
    void absentAuthenticationAndDisabledSecurityNeverReadBusinessData() throws Exception {
        SecurityContextHolder.clearContext();
        submit(request()).andExpect(status().isUnauthorized()).andExpect(jsonPath("$.evidence").isEmpty());
        login();
        mvc = controller(false);
        submit(request()).andExpect(status().isUnauthorized());
        verifyNoInteractions(reviews);
    }

    @Test
    void invalidAndExtraArgumentsCannotSelectOrganizationOrTools() throws Exception {
        for (String body : List.of("{}", "null", "[]",
                "{\"tool\":\"confirm\",\"arguments\":{}}",
                request().replace("\"sessionId\":", "\"org\":\"other\",\"sessionId\":"),
                request().replace("\"arguments\":", "\"token\":\"secret\",\"arguments\":"),
                request().replace(id.toString(), "1-1-1-1-1"))) {
            submit(body).andExpect(status().isUnprocessableEntity())
                    .andExpect(jsonPath("$.status").value("invalid_arguments"));
        }
        verifyNoInteractions(reviews);
    }

    @Test
    void deniedOrMissingSessionHasTheSameEmptyEnvelope() throws Exception {
        when(reviews.inspectSessionFacts(id)).thenThrow(InventoryException.notFound());
        submit(request()).andExpect(status().isNotFound())
                .andExpect(jsonPath("$.status").value("not_found_or_forbidden"))
                .andExpect(jsonPath("$.data").isEmpty()).andExpect(jsonPath("$.evidence").isEmpty());
        verify(reviews, never()).sessionMedia(any());
    }

    @Test
    void secondReadDenialDoesNotLeakTheFirstSnapshot() throws Exception {
        when(reviews.inspectSessionFacts(id)).thenReturn(new InventoryReviewService.SessionInspectionSnapshot(
                id, "2026-11-02", "confirmed", 10, 12, "succeeded"));
        when(reviews.sessionMedia(id)).thenThrow(InventoryException.notFound());
        submit(request()).andExpect(status().isNotFound()).andExpect(jsonPath("$.data").isEmpty());
    }

    @Test
    void unavailableDatabaseDoesNotBecomeZeroOrExposeExceptionDetail() throws Exception {
        when(reviews.inspectSessionFacts(id)).thenThrow(new DataAccessResourceFailureException("private-host-secret"));
        submit(request()).andExpect(status().isServiceUnavailable())
                .andExpect(jsonPath("$.status").value("unavailable"))
                .andExpect(jsonPath("$.data").isEmpty()).andExpect(jsonPath("$.evidence").isEmpty());
    }

    private MockMvc controller(boolean enabled) {
        return MockMvcBuilders.standaloneSetup(new AssistantToolController(new SessionInspectionTool(reviews, enabled),
                        mock(com.smartfarm.inventory.inventory.application.InventoryEvidenceTools.class)))
                .setMessageConverters(new org.springframework.http.converter.json.MappingJackson2HttpMessageConverter(
                        new com.fasterxml.jackson.databind.ObjectMapper().findAndRegisterModules()
                                .setSerializationInclusion(com.fasterxml.jackson.annotation.JsonInclude.Include.NON_NULL)))
                .build();
    }

    private void login() {
        var jwt = Jwt.withTokenValue("synthetic").header("alg", "RS256").subject("fixture")
                .claim("active_organization_id", UUID.randomUUID().toString()).build();
        SecurityContextHolder.getContext().setAuthentication(new JwtAuthenticationToken(jwt, List.of()));
    }

    private void facts(String state, Integer candidate, Integer confirmed, String inference) {
        when(reviews.inspectSessionFacts(id)).thenReturn(new InventoryReviewService.SessionInspectionSnapshot(
                id, "2026-11-02", state, confirmed, candidate, inference));
        when(reviews.sessionMedia(id)).thenReturn(List.of(new InventoryReviewService.MediaEvidenceView(
                UUID.randomUUID(), "center", "image/jpeg", 42, "ready", false, false)));
    }

    private String request() {
        return "{\"tool\":\"inspect_session\",\"arguments\":{\"sessionId\":\"" + id + "\"}}";
    }

    private org.springframework.test.web.servlet.ResultActions submit(String body) throws Exception {
        return mvc.perform(post("/api/v1/assistant/tools/inspect-session")
                .contentType(MediaType.APPLICATION_JSON).content(body));
    }
}
