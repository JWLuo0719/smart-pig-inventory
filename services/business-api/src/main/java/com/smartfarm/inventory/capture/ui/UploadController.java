package com.smartfarm.inventory.capture.ui;

import com.smartfarm.inventory.capture.application.CommitUploadResult;
import com.smartfarm.inventory.capture.application.UploadCommand;
import com.smartfarm.inventory.capture.application.UploadOutcome;
import com.smartfarm.inventory.capture.application.UploadPackageView;
import com.smartfarm.inventory.capture.application.UploadService;
import com.smartfarm.inventory.capture.domain.CaptureKind;
import com.smartfarm.inventory.capture.domain.CaptureManifest;
import com.smartfarm.inventory.capture.domain.ManifestAsset;
import com.smartfarm.inventory.capture.domain.Roi;
import com.smartfarm.inventory.capture.domain.ViewPosition;
import jakarta.servlet.http.HttpServletRequest;
import jakarta.validation.Valid;
import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.NotNull;
import jakarta.validation.constraints.Pattern;
import jakarta.validation.constraints.Positive;
import java.io.IOException;
import java.math.BigDecimal;
import java.time.Instant;
import java.time.LocalDate;
import java.util.List;
import java.util.Map;
import java.util.UUID;
import org.springframework.http.HttpStatus;
import org.springframework.http.MediaType;
import org.springframework.http.ResponseEntity;
import org.springframework.validation.annotation.Validated;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.PutMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestHeader;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

@RestController
@Validated
@RequestMapping("/api/v1/upload-packages")
public class UploadController {
    private final UploadService service;

    public UploadController(UploadService service) {
        this.service = service;
    }

    @PostMapping
    ResponseEntity<UploadPackageResponse> createPackage(
            @RequestHeader("X-Idempotency-Key") UUID idempotencyKey,
            @Valid @RequestBody CreateUploadPackageRequest request) {
        UploadOutcome<UploadPackageView> outcome = service.createPackage(request.toCommand(), idempotencyKey);
        return ResponseEntity.status(outcome.httpStatus()).body(UploadPackageResponse.from(outcome.body()));
    }

    @GetMapping("/{packageId}")
    UploadPackageResponse getPackage(@PathVariable UUID packageId) {
        return UploadPackageResponse.from(service.getPackage(packageId));
    }

    @PutMapping(value = "/{packageId}/blobs/{assetId}", consumes = MediaType.APPLICATION_OCTET_STREAM_VALUE)
    ResponseEntity<Void> putBlob(
            @PathVariable UUID packageId,
            @PathVariable UUID assetId,
            @RequestHeader("X-Idempotency-Key") UUID idempotencyKey,
            @RequestHeader("X-Content-SHA256") String sha256,
            HttpServletRequest request) throws IOException {
        UploadOutcome<Void> outcome = service.putBlob(
                packageId, assetId, idempotencyKey, sha256, request.getContentLengthLong(), request.getInputStream());
        return ResponseEntity.status(outcome.httpStatus()).build();
    }

    @PutMapping(value = "/{packageId}/manifest", consumes = MediaType.APPLICATION_JSON_VALUE)
    ResponseEntity<Void> putManifest(
            @PathVariable UUID packageId,
            @RequestHeader("X-Idempotency-Key") UUID idempotencyKey,
            @Valid @RequestBody CaptureManifestRequest request) {
        UploadOutcome<Void> outcome = service.putManifest(packageId, idempotencyKey, request.toDomain());
        return ResponseEntity.status(outcome.httpStatus()).build();
    }

    @PostMapping("/{packageId}/commit")
    ResponseEntity<CommitResultResponse> commit(
            @PathVariable UUID packageId,
            @RequestHeader("X-Idempotency-Key") UUID idempotencyKey,
            HttpServletRequest request) {
        String correlationId = (String) request.getAttribute(com.smartfarm.inventory.common.CorrelationIdFilter.ATTRIBUTE);
        UploadOutcome<CommitUploadResult> outcome = service.commit(packageId, idempotencyKey, correlationId);
        return ResponseEntity.status(outcome.httpStatus()).body(CommitResultResponse.from(outcome.body()));
    }

    record CreateUploadPackageRequest(
            @NotNull UUID clientPackageId,
            @NotNull UUID organizationId,
            @NotNull UUID penId,
            @NotNull LocalDate businessDate,
            @NotBlank String captureKind) {
        UploadCommand toCommand() {
            return new UploadCommand(clientPackageId, organizationId, penId, businessDate, CaptureKind.fromWire(captureKind));
        }
    }

    record CaptureManifestRequest(
            @NotNull UUID captureSetId,
            @NotBlank String captureKind,
            @NotNull UUID penId,
            @NotNull @jakarta.validation.constraints.Size(min = 1, max = 3) List<@Valid ManifestAssetRequest> assets) {
        CaptureManifest toDomain() {
            return new CaptureManifest(captureSetId, CaptureKind.fromWire(captureKind), penId,
                    assets.stream().map(ManifestAssetRequest::toDomain).toList());
        }
    }

    record ManifestAssetRequest(
            @NotNull UUID assetId,
            @NotBlank String viewPosition,
            @NotNull Instant capturedAt,
            @NotBlank @jakarta.validation.constraints.Size(max = 255) String originalName,
            @Positive int width,
            @Positive int height,
            @NotBlank @Pattern(regexp = "^[a-f0-9]{64}$") String sha256,
            @jakarta.validation.constraints.Pattern(regexp = "^[a-f0-9]{16}$") String perceptualHash,
            @Positive long byteSize,
            @NotBlank String mediaType,
            @NotNull Map<String, Object> exif,
            RoiRequest roi) {
        ManifestAsset toDomain() {
            return new ManifestAsset(assetId, ViewPosition.fromWire(viewPosition), capturedAt, originalName, width, height,
                    sha256, perceptualHash, byteSize, mediaType, exif, roi == null ? null : roi.toDomain());
        }
    }

    record RoiRequest(@NotNull BigDecimal x, @NotNull BigDecimal y, @NotNull BigDecimal width, @NotNull BigDecimal height) {
        Roi toDomain() {
            return new Roi(x, y, width, height);
        }
    }

    record UploadPackageResponse(UUID id, UUID clientPackageId, String state, List<UUID> existingAssets) {
        static UploadPackageResponse from(UploadPackageView view) {
            return new UploadPackageResponse(view.id(), view.clientPackageId(), view.state().databaseValue(), view.existingAssets());
        }
    }

    record CommitResultResponse(UUID packageId, UUID sessionId, UUID inferenceJobId, String status) {
        static CommitResultResponse from(CommitUploadResult result) {
            return new CommitResultResponse(result.packageId(), result.sessionId(), result.inferenceJobId(), result.status());
        }
    }
}
