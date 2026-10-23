package com.smartfarm.inventory.inventory.ui;

import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.eq;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.verifyNoInteractions;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.post;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

import com.smartfarm.inventory.inventory.application.InventoryReportExportService;
import com.smartfarm.inventory.inventory.application.InventoryReviewService;
import java.util.UUID;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;
import org.springframework.http.MediaType;
import org.springframework.test.web.servlet.MockMvc;
import org.springframework.test.web.servlet.setup.MockMvcBuilders;

/** Exercises JSON binding and validation before a malformed request can change inventory. */
@ExtendWith(MockitoExtension.class)
class InventoryReviewRequestValidationTest {
    @Mock private InventoryReviewService reviews;
    @Mock private InventoryReportExportService exports;
    private MockMvc mvc;
    private final UUID sessionId = UUID.randomUUID();
    private final UUID idempotencyKey = UUID.randomUUID();

    @BeforeEach
    void setUp() {
        mvc = MockMvcBuilders.standaloneSetup(new InventoryReviewController(reviews, exports))
                .setControllerAdvice(new InventoryProblemHandler()).build();
    }

    @Test
    void confirmationRejectsMissingNullAndNegativeQuantity() throws Exception {
        for (String body : new String[] {"{}", "{\"confirmedCount\":null}", "{\"confirmedCount\":-1}"}) {
            submit("confirm", body).andExpect(status().isUnprocessableEntity());
        }
        verify(reviews, never()).confirm(any(), org.mockito.ArgumentMatchers.anyInt(), any(), any(), any());
    }

    @Test
    void correctionRejectsMissingNullAndNegativeQuantity() throws Exception {
        for (String value : new String[] {"", "\"correctedCount\":null,", "\"correctedCount\":-1,"}) {
            submit("corrections", "{" + value + "\"reason\":\"现场两人核对确认更正依据\"}")
                    .andExpect(status().isUnprocessableEntity());
        }
        verify(reviews, never()).correct(any(), org.mockito.ArgumentMatchers.anyInt(), any(), any(), any());
    }

    @Test
    void explicitZeroRemainsAValidConfirmationAndCorrection() throws Exception {
        String reason = "现场两人核对确认空栏依据";
        submit("confirm", "{\"confirmedCount\":0,\"reason\":\"" + reason + "\"}")
                .andExpect(status().isOk());
        submit("corrections", "{\"correctedCount\":0,\"reason\":\"" + reason + "\"}")
                .andExpect(status().isOk());
        verify(reviews).confirm(eq(sessionId), eq(0), eq(reason), eq(idempotencyKey), any());
        verify(reviews).correct(eq(sessionId), eq(0), eq(reason), eq(idempotencyKey), any());
    }

    @Test
    void confirmationNeverCoercesFractionsStringsBooleansOrOverflowToAnInteger() throws Exception {
        rejectNonIntegerTokens("confirm", "confirmedCount");
    }

    @Test
    void correctionNeverCoercesFractionsStringsBooleansOrOverflowToAnInteger() throws Exception {
        rejectNonIntegerTokens("corrections", "correctedCount");
    }

    private void rejectNonIntegerTokens(String action, String field) throws Exception {
        for (String token : new String[] {"1.5", "1.0", "1e0", "\"0\"", "true", "false", "2147483648", "-2147483649", "[]", "{}"}) {
            submit(action, "{\"" + field + "\":" + token + ",\"reason\":\"现场两人核对确认数量依据\"}")
                    .andExpect(status().isBadRequest());
        }
        verifyNoInteractions(reviews);
    }

    private org.springframework.test.web.servlet.ResultActions submit(String action, String body) throws Exception {
        return mvc.perform(post("/api/v1/inventory-sessions/" + sessionId + "/" + action)
                .header("X-Idempotency-Key", idempotencyKey).contentType(MediaType.APPLICATION_JSON).content(body));
    }
}
