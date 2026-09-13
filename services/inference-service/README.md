# Inference service

This service is an isolation boundary, not the business authority. The API enqueues versioned jobs; workers call a configured `CountingProvider`. The default provider returns `review_required` with no count.

No Ultralytics or research repository source is included in the default runtime. A future YOLOv13 adapter must be added as a separately reviewed provider with model checksum and regression evidence.

The external HTTP boundary uses separate positive timeouts: `YOLO_HTTP_CONNECT_TIMEOUT_SECONDS` defaults to 10 seconds and `YOLO_HTTP_TIMEOUT_SECONDS` defaults to 120 seconds. Provider timeouts become an auditable terminal `failed` callback with no count; transient callback delivery failures are retried by Celery with the original job id.

Every result callback requires the same non-empty `INFERENCE_CALLBACK_TOKEN` on the worker and business API. `SECURITY_ENABLED=false` only affects end-user authentication; it never bypasses callback service-key validation. A missing/unconfigured/wrong callback key returns 401, which the worker treats as a permanent delivery failure; fix configuration before retrying. End-user JWTs cannot replace this service credential. Validate this boundary with `scripts/run-callback-auth-e2e.ps1` in its fixed isolated project.

For `http-yolo` and `research-http-yolo`, `/health/ready` also calls the external Runner readiness endpoint (`YOLO_HTTP_READY_ENDPOINT`, or the Runner origin plus `/health/ready`). Readiness fails closed unless the Runner reports `ready=true` and its model key, version, checksum, and adapter version match the configured product identity. The default unavailable Provider remains process-ready with `counting_available=false`.

Provider failures are normalized to safe codes such as `PROVIDER_TIMEOUT`, `PROVIDER_UNAVAILABLE`, `PROVIDER_HTTP_STATUS`, `PROVIDER_INVALID_RESULT`, and `PROVIDER_CONTRACT_ERROR`; raw endpoint errors are not exposed to product clients.

Research release evidence is generated outside the service image with `scripts/model_release_gate.py`. The tool verifies the weight SHA-256 against the full val/test regression summary, emits only a file name rather than an external path, and forces every candidate to remain unapproved, manual-review-only, and blocked on license, business gold-set, and owner approval. `run-team-yolo-regression.ps1` can build the manifest and compare an existing immutable local baseline when `ReleaseModelKey`, `ReleaseModelVersion`, and `RegressionBaseline` are supplied. It never creates or replaces a baseline implicitly.

