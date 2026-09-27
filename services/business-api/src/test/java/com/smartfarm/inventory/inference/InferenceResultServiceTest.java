package com.smartfarm.inventory.inference;

import static org.assertj.core.api.Assertions.assertThat;
import static org.mockito.ArgumentMatchers.eq;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

import com.fasterxml.jackson.databind.ObjectMapper;
import java.util.ArrayList;
import java.util.List;
import java.util.Optional;
import java.util.UUID;
import org.junit.jupiter.api.Test;
import org.mockito.ArgumentCaptor;

/**
 * 结果回调的降级门禁：三图与视频都必须先有经验证的 Provider，才可能出现自动候选值。
 *
 * <p>这些用例只依赖 Mockito 与纯 Java，不需要 Docker、MySQL 或对象存储，因此可以在任意
 * 工作站上复现；数据库层的完整闭环仍由 Testcontainers 集成测试覆盖。
 */
class InferenceResultServiceTest {
    private static final String MODEL_KEY = "pig-yolov13";
    private static final String MODEL_VERSION = "v3-aligned";
    private static final String MODEL_CHECKSUM = "f".repeat(64);
    private static final String ADAPTER_VERSION = "http-v1";

    private record Outcome(InferenceCallbackResult stored, Integer candidateCount) { }

    @Test
    void videoSuccessStaysManualUntilTheVideoProviderIsValidated() {
        Outcome outcome = accept("video", succeeded(7), false, false);

        assertThat(outcome.stored().status()).isEqualTo("review_required");
        assertThat(outcome.stored().count()).isNull();
        assertThat(outcome.stored().warnings()).anyMatch(warning -> warning.contains("validated video provider"));
        assertThat(outcome.candidateCount()).isNull();
    }

    @Test
    void videoSuccessBecomesACandidateOnlyOnceTheVideoGateIsOn() {
        Outcome outcome = accept("video", succeeded(7), false, true);

        assertThat(outcome.stored().status()).isEqualTo("succeeded");
        assertThat(outcome.stored().count()).isEqualTo(7);
        assertThat(outcome.candidateCount()).isEqualTo(7);
    }

    @Test
    void failedVideoResultIsNeverRewritten() {
        InferenceCallbackResult failed = new InferenceCallbackResult(
                "failed", null, List.of(), List.of("provider failed"), MODEL_KEY, MODEL_VERSION, MODEL_CHECKSUM,
                ADAPTER_VERSION, "provider-error", 3, "PROVIDER_TIMEOUT", "runner timed out");

        Outcome outcome = accept("video", failed, false, false);

        assertThat(outcome.stored().status()).isEqualTo("failed");
        assertThat(outcome.stored().failureCode()).isEqualTo("PROVIDER_TIMEOUT");
    }

    @Test
    void multiViewSuccessStaysManualUntilTheMultiViewGateIsOn() {
        Outcome outcome = accept("left_center_right", succeeded(12), false, false);

        assertThat(outcome.stored().status()).isEqualTo("review_required");
        assertThat(outcome.stored().count()).isNull();
        assertThat(outcome.stored().warnings())
                .anyMatch(warning -> warning.contains("Multi-view inference requires"));
        assertThat(outcome.candidateCount()).isNull();
    }

    @Test
    void multiViewSuccessBecomesACandidateOnlyOnceTheGateIsOn() {
        Outcome outcome = accept("left_center_right", succeeded(12), true, false);

        assertThat(outcome.stored().status()).isEqualTo("succeeded");
        assertThat(outcome.candidateCount()).isEqualTo(12);
    }

    @Test
    void alreadyReviewedMultiViewEvidenceIsLeftUntouchedAndNeverYieldsACandidate() {
        Outcome outcome = accept("left_center_right", reviewRequired(3), false, false);

        assertThat(outcome.stored().status()).isEqualTo("review_required");
        assertThat(outcome.stored().warnings()).containsExactly("Runner asked for review");
        assertThat(outcome.candidateCount()).isNull();
    }

    @Test
    void singleImageKeepsItsExistingCandidateBehaviour() {
        Outcome succeededOutcome = accept("single", succeeded(5), false, false);
        Outcome reviewedOutcome = accept("single", reviewRequired(3), false, false);

        assertThat(succeededOutcome.candidateCount()).isEqualTo(5);
        assertThat(reviewedOutcome.candidateCount()).isEqualTo(3);
    }

    @Test
    void anUnknownCaptureKindFailsClosed() {
        Outcome outcome = accept("mystery", succeeded(4), true, true);

        assertThat(outcome.stored().status()).isEqualTo("review_required");
        assertThat(outcome.stored().count()).isNull();
        assertThat(outcome.stored().warnings())
                .anyMatch(warning -> warning.contains("unrecognized capture kind"));
        assertThat(outcome.candidateCount()).isNull();
    }

    private Outcome accept(
            String captureKind,
            InferenceCallbackResult received,
            boolean multiViewAutoCountEnabled,
            boolean videoAutoCountEnabled) {
        JdbcInferenceRepository repository = mock(JdbcInferenceRepository.class);
        UUID jobId = UUID.randomUUID();
        UUID sessionId = UUID.randomUUID();
        when(repository.lockJob(jobId)).thenReturn(Optional.of(
                new JdbcInferenceRepository.LockedJob(jobId, "processing", sessionId, captureKind)));
        when(repository.findReceipt(jobId)).thenReturn(Optional.empty());

        new InferenceResultService(repository, new ObjectMapper(), multiViewAutoCountEnabled, videoAutoCountEnabled)
                .accept(jobId, received);

        ArgumentCaptor<InferenceCallbackResult> stored = ArgumentCaptor.forClass(InferenceCallbackResult.class);
        verify(repository).insertResult(eq(jobId), stored.capture());
        ArgumentCaptor<Integer> candidateCount = ArgumentCaptor.forClass(Integer.class);
        verify(repository).markSessionForReview(eq(sessionId), candidateCount.capture());
        return new Outcome(stored.getValue(), candidateCount.getValue());
    }

    private InferenceCallbackResult succeeded(int count) {
        return new InferenceCallbackResult(
                "succeeded", count, List.of(), List.of(), MODEL_KEY, MODEL_VERSION, MODEL_CHECKSUM,
                ADAPTER_VERSION, "runner", 12, null, null);
    }

    private InferenceCallbackResult reviewRequired(int detectionCount) {
        List<InferenceCallbackResult.Detection> detections = new ArrayList<>();
        for (int index = 0; index < detectionCount; index++) {
            detections.add(new InferenceCallbackResult.Detection(
                    UUID.randomUUID(), List.of(0.1, 0.1, 0.2, 0.2), 0.9, 0));
        }
        return new InferenceCallbackResult(
                "review_required", null, detections, List.of("Runner asked for review"), MODEL_KEY, MODEL_VERSION,
                MODEL_CHECKSUM, ADAPTER_VERSION, "runner", 12, null, null);
    }
}
