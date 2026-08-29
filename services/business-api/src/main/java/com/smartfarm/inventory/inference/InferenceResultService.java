package com.smartfarm.inventory.inference;

import com.fasterxml.jackson.databind.ObjectMapper;
import com.fasterxml.jackson.databind.SerializationFeature;
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

    public InferenceResultService(
            JdbcInferenceRepository repository,
            ObjectMapper objectMapper,
            @Value("${app.inference.multiview-auto-count-enabled:false}") boolean multiViewAutoCountEnabled) {
        this.repository = repository;
        this.objectMapper = objectMapper.copy().configure(SerializationFeature.ORDER_MAP_ENTRIES_BY_KEYS, true);
        this.multiViewAutoCountEnabled = multiViewAutoCountEnabled;
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
        repository.markSessionForReview(job.sessionId(), result.isSucceeded() ? result.count() : null);
        return CallbackOutcome.CREATED;
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
        if ("left_center_right".equals(captureKind) && result.isSucceeded() && !multiViewAutoCountEnabled) {
            return result.requireManualReview("Multi-view inference requires a validated multi-view provider before any automatic count is used");
        }
        return result;
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
