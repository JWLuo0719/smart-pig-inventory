# AGENTS.md

Project-local rules for future agents and contributors.

## Source of truth

- `docs/product/PRD.md`: product scope and business rules.
- `docs/product/acceptance-criteria.md`: release acceptance gates.
- `docs/product/non-functional-requirements.md`: measurable quality targets.
- `docs/product/requirements-traceability.md`: implementation and verification status.
- `docs/architecture.md`: B+ system architecture and module ownership.
- `docs/deployment/pilot-baseline.md`: pilot device and edge-server sizing assumptions.
- `contracts/openapi.yaml`: external HTTP contract; change contract first.
- `CURRENT_HANDOFF.md`: first-read operational handoff for a new conversation.
- `PROJECT_STATUS.md` and `NEXT_STEPS.md`: detailed current evidence and ordered remaining work.
- `docs/development/workstation-setup.md`: verified workstation setup and local startup procedure.
- `docs/development/test-data-governance.md`: test-data authorization, storage, and fixture boundaries.

## Product and legacy boundaries

- The active product stack is Flutter + Next.js + Spring Boot/MySQL + MinIO + Redis/Celery-backed Python inference.
- `services/backend/` is the frozen Django prototype. Do not add product features there.
- `eg/` is a read-only legacy reference supplied by prior students. Never copy its source, SQL, assets, models, names, or copywriting into the product. Reimplement behavior from independently written requirements.
- The model research repositories remain separate. Product code talks to inference only through a versioned provider contract.
- AGPL/GPL code must not be linked or copied into the proprietary mainline. MinIO is a replaceable external service and still needs a distribution/legal decision before release.

## Engineering rules

- Release delivery priority follows `NEXT_STEPS.md`: signed Android Release with real single-image AI candidate counting, then consolidated authorized real-pig/manual acceptance. Keep automated regression during development. Do not treat Release signing as model approval or automatically promote AI candidates to confirmed report values. Release signing must not fall back to the debug key; keep signing secrets out of Git.
- Android Release workflow: `scripts/initialize-release-signing.ps1` refuses existing keys; `scripts/build-release-apk.ps1` pins the expected certificate and verifies APK metadata/cleartext policy; `scripts/test-release-configuration.ps1` checks Gradle gates. See `docs/development/android-release.md`. A `-BuildOnly` APK with a reserved endpoint is only build evidence, never a connected acceptance candidate. Preserve the local signing identity and existing Debug device drafts; do not uninstall or rotate keys to work around signature mismatch.
- Before runtime acceptance, verify deployed images and Flyway migrations match the intended source version. A healthy old image is not evidence for current code. Process-scoped Compose environment overrides must be passed again to every separate shell invocation, including fixture scripts that recreate services. Preserve device drafts when planning transitions between debug and release signing identities.

- Android first; keep Flutter platform-neutral where practical.
- Offline state is explicit. Never show a count before the server returns a real result.
- Upload follows create package -> blobs -> manifest -> commit and is idempotent at every step.
- Exact duplicate images are rejected by organization-scoped SHA-256 uniqueness. Perceptual similarity only creates a review warning.
- Multi-view images are one capture set. Never sum left/center/right results until a validated deduplication provider exists.
- Mobile home, gallery, task, and profile surfaces must read organization-scoped repositories or APIs. Do not ship hard-coded farm names, counts, progress, queue sizes, or demo activity in product screens.
- Every admin workflow endpoint must be admitted explicitly by the same-origin backend route policy and covered by a method/path allow-list test. Keep access and refresh tokens memory-only; a 401 retry must rotate once and replay the original request without changing its idempotency key.
- Admin optional panels must distinguish loading, known permission denial, request failure, and successful empty data. Only a successful list response may display zero. Derive presentation permissions from the active organization, keep backend authorization authoritative, and never infer permission denial from a masked 404 alone. Hide stale panel rows during reload and verify error recovery in the fixed admin runtime stack.
- An administrative inference retry creates a new job in the same immutable linear lineage. Never reopen or overwrite the failed attempt; preserve its media, failure evidence, requested model identity, and audit history. The same idempotency key and normalized reason replay the same successor, and a late retry callback must not demote a confirmed session.
- Late callbacks must also leave `superseded` evidence sessions unchanged after a correction; they may finalize the retry job, but must not reopen historical inventory versions or replace the current task projection.
- Any media referenced by a confirmed result is locked. Administrative overrides require a reason and an audit event.
- A post-confirmation correction creates a new confirmed inventory-session version that references the original evidence session and supersedes exactly one current version. Never update or delete the historical confirmed row; identical idempotency key/count/normalized reason must replay the same successor.
- Enabling the inference dispatcher requires a non-empty callback token even when end-user security is disabled for local development.
- Callback service-key authentication is always enforced independently of `SECURITY_ENABLED`. A missing/blank configured key, absent/wrong supplied key, or end-user JWT without the service key cannot authorize a callback. Keep dispatcher startup validation and callback request validation as separate fail-closed gates.
- Global monitoring endpoints require the independent `MONITORING_SERVICE_KEY` even with end-user security disabled; ordinary/admin JWTs never authorize global metrics. Keep labels bounded and identity/secret-free. Rolling database snapshots are gauges (not counters), failed snapshots are unknown (not zero), and monitoring must use a scheduling thread separate from inference dispatch. Do not equate Outbox/jobs with Broker queue length or Provider latency with end-to-end P95.
- PDF/XLSX inventory exports must read one organization-scoped confirmed-only snapshot. Never export candidate, failed, unconfirmed, other-organization, model identity, failure detail, media, or internal object URL fields. Keep the 366-day and 10,000-record limits unless the contract and capacity evidence change first; preserve formula-injection-safe XLSX strings and the configured embedded Chinese PDF font boundary.
- Database changes use Flyway. Do not edit an applied migration; add a new one.
- No real credentials, production data, or model weights in Git.
- The external `agent-base/dataset` research dataset is read-only. Product code may generate an ignored local manifest from it but must not copy its images, labels, hashes, or absolute paths into tracked files, images, Docker contexts, or CI artifacts.

## Research model release boundary

仅当本次任务涉及 Research model release boundary 时，读取 [Research model release boundary](docs/agent-guidance/research-model-release-boundary.md)；其中原有数据、安全、授权及验收约束继续适用于该工作流。

## Verification

- Spring: `mvn test` and `mvn verify` from `services/business-api`.
- Admin: `pnpm test`, `pnpm lint`, `pnpm typecheck`, and `pnpm build` from `apps/admin-web`.
- Flutter: `flutter analyze`, `flutter test`, and `flutter build apk --debug` from `apps/mobile`.
- Inference: `python -m pytest` from `services/inference-service`.
- Infrastructure: `docker compose config --quiet` from repository root.
- Research release tooling: validate the real local manifest with `scripts/model_release_gate.py`, run the full `pig-inventory-p1-fault` fault E2E after changing the test Runner, and run the isolated rollback rehearsal after changing model identity/readiness behavior.
- Report export: run `scripts/run-report-export-e2e.ps1` only in `pig-inventory-p1-report-export`; visually inspect both generated formats after renderer/layout changes. Never repoint it at P0 or commit `test-assets/generated/` evidence.
- Admin runtime: `pwsh -NoProfile -File scripts/run-admin-runtime-e2e.ps1` uses only `pig-inventory-p0-admin-runtime`, loopback port 8093, synthetic identities/media, and a fresh system Edge process. See `docs/development/admin-runtime-e2e.md`. Never reuse P0 volumes or treat CLI exit code 0/empty JSON as success; require the sanitized final semantic readback. Successful cleanup removes only this test project's containers/network and preserves volumes.
- Callback authentication: `pwsh -NoProfile -File scripts/run-callback-auth-e2e.ps1` uses only `pig-inventory-p0-callback-auth` and loopback port 8094. It verifies both user-security modes, rejected-request no-write behavior, accepted/replayed/conflicting results, and unconfigured-key rejection against real HTTP/MySQL. Fixtures are synthetic callback-only records; never repoint the script at P0 or delete its volumes.
- Observability: `pwsh -NoProfile -File scripts/run-observability-e2e.ps1` uses only `pig-inventory-p0-observability` and loopback port 8095. Run promtool tests after changing rules; keep diagnostic thresholds distinct from approved production SLOs. See `docs/development/business-observability.md`; never reuse P0 volumes or configure external receivers without explicit user choices.

- LAN acceptance uses scripts/configure-lan-acceptance.ps1 and docs/development/lan-real-pig-acceptance.md: private CA is scoped to pig-inventory.local only; never bypass TLS checks. Preserve signing/TLS identities and Debug drafts. Current-user login startup is not verified boot recovery. Phone/firewall/mDNS acceptance remains separate from localhost health; renew the 90-day TLS identity only with a controlled APK rebuild.

## Task completion and prompt scope

按本次变更涉及的 Spring、Admin、Flutter、Inference 或基础设施模块执行 AGENTS 的 Verification；业务结果保持组织隔离、幂等、人工确认和历史版本不可变。APK 构建、真机联通、真实猪只验收和模型批准分别记录，任何一项不能替代另一项。

编写任务提示词、确认非平凡任务验收或准备交接时，读取 [任务契约](docs/TASK_CONTRACT.md)。普通小改动直接使用当前请求和上述标准，不额外执行无关研究、安装或发布。历史状态/提示词仅作证据；新的运行结论以本次验证为准。

## Backup recovery tooling

- `scripts/inventory_snapshot.py` only snapshots fully stopped, project-owned MySQL/Redis/MinIO named volumes and restores into a distinct project with no existing target volumes. Never bypass these guards or run a cold copy against live storage. Snapshots contain sensitive data and stay outside Git/release bundles on protected storage. Physical recovery requires the recorded original service images and separate business readback.
- `python scripts/test_inventory_snapshot.py` and `python scripts/run_snapshot_e2e.py` verify recovery tooling. The rehearsal uses only generated `pig-inventory-recovery-source-*` / `pig-inventory-recovery-target-*` projects and loopback 8096, never P0 or production volumes. Successful cleanup preserves all volumes. See `docs/deployment/backup-recovery.md`.
