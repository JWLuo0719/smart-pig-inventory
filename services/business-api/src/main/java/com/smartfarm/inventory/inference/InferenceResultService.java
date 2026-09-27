package com.smartfarm.inventory.inference;

import com.fasterxml.jackson.databind.ObjectMapper;
import com.fasterxml.jackson.databind.SerializationFeature;
import com.smartfarm.inventory.capture.domain.CaptureSetPolicy;
import java.nio.charset.StandardCharsets;
import java.security.MessageDigest;
import java.security.NoSuchAlgorithmException;
import java.util.HexFormat;
import java.util.UUID;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

@Service
public class InferenceResultService {
    private final JdbcInferenceRepository repository;
    private final ObjectMapper objectMapper;
    private final boolean multiViewAutoCountEnabled;
    private final boolean videoAutoCountEnabled;

    public InferenceResultService(
            JdbcInferenceRepository repository,
            ObjectMapper objectMapper,
            @Value("${app.inference.multiview-auto-count-enabled:false}") boolean multiViewAutoCountEnabled,
            @Value("${app.inference.video-auto-count-enabled:false}") boolean videoAutoCountEnabled) {
        this.repository = repository;
        this.objectMapper = objectMapper.copy().configure(SerializationFeature.ORDER_MAP_ENTRIES_BY_KEYS, true);
        this.multiViewAutoCountEnabled = multiViewAutoCountEnabled;
        this.videoAutoCountEnabled = videoAutoCountEnabled;
    }

    @Transactional
    public CallbackOutcome accept(UUID jobId, InferenceCallbackResult received) {
        validate(received);
        JdbcInferenceRepository.LockedJob job = repository.lockJob(jobId).orElseThrow(InferenceException::notFound);
        InferenceCallbackResult result = normalizeForCaptureKind(job.captureKind(), received);
        String fingerprint = fingerprint(result);
        var existing = repository.findReceipt(jobId);
        if (existing.isPresent()) {
            if (existing.get().equals(fingerprint)) {
                return CallbackOutcome.REPLAYED;
            }
            throw InferenceException.conflict("The inference job already has a different final result");
        }
        if (!("submitted".equals(job.status()) || "processing".equals(job.status()))) {
            throw InferenceException.conflict("The inference job is not awaiting a result");
        }

        repository.insertResult(jobId, result);
        repository.insertReceipt(jobId, fingerprint);
        repository.finishJob(jobId, result);
        repository.markSessionForReview(job.sessionId(), candidateCount(job.captureKind(), result));
        return CallbackOutcome.CREATED;
    }

    private Integer candidateCount(String captureKind, InferenceCallbackResult result) {
        if (result.isSucceeded()) {
            return result.count();
        }
        if ("single".equals(captureKind)
                && result.isReviewRequired()
                && result.detections() != null
                && !result.detections().isEmpty()) {
            return result.detections().size();
        }
        return null;
    }

    private void validate(InferenceCallbackResult result) {
        if (!(result.isSucceeded() || result.isReviewRequired() || result.isFailed())) {
            throw InferenceException.invalid("Unsupported inference result status");
        }
        if (result.isSucceeded() && result.count() == null) {
            throw InferenceException.invalid("A succeeded inference result requires a count");
        }
        if (!result.isSucceeded() && result.count() != null) {
            throw InferenceException.invalid("Only a succeeded inference result may contain a count");
        }
    }

    private InferenceCallbackResult normalizeForCaptureKind(String captureKind, InferenceCallbackResult result) {
        if (result.isFailed()) {
            // 失败结果是终态证据，不因采集类型被改写。
            return result;
        }
        if (!CaptureSetPolicy.requiresManualReview(captureKind, multiViewAutoCountEnabled, videoAutoCountEnabled)) {
            return result;
        }
        if ("left_center_right".equals(captureKind) && !result.isSucceeded()) {
            // 三图只有在一个 Provider 声称成功时才需要按门禁降级；已复核的三图结果保持原样。
            return result;
        }
        return result.requireManualReview(reviewReason(captureKind));
    }

    private static String reviewReason(String captureKind) {
        return switch (captureKind) {
            case "video" -> "Video evidence requires a validated video provider before any automatic count is used";
            case "left_center_right" ->
                "Multi-view inference requires a validated multi-view provider before any automatic count is used";
            default -> "An unrecognized capture kind requires manual review";
        };
    }

    private String fingerprint(InferenceCallbackResult result) {
        try {
            byte[] canonicalJson = objectMapper.writeValueAsBytes(result);
            return HexFormat.of().formatHex(MessageDigest.getInstance("SHA-256").digest(canonicalJson));
        } catch (NoSuchAlgorithmException | com.fasterxml.jackson.core.JsonProcessingException exception) {
            throw new IllegalStateException("Cannot fingerprint inference result", exception);
        }
    }

    public enum CallbackOutcome { CREATED, REPLAYED }
}
