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
- `PROJECT_STATUS.md` and `NEXT_STEPS.md`: current handoff state.
- `docs/development/workstation-setup.md`: verified workstation setup and local startup procedure.
- `docs/development/test-data-governance.md`: test-data authorization, storage, and fixture boundaries.

## Product and legacy boundaries

- The active product stack is Flutter + Next.js + Spring Boot/MySQL + MinIO + Redis/Celery-backed Python inference.
- `services/backend/` is the frozen Django prototype. Do not add product features there.
- `eg/` is a read-only legacy reference supplied by prior students. Never copy its source, SQL, assets, models, names, or copywriting into the product. Reimplement behavior from independently written requirements.
- The model research repositories remain separate. Product code talks to inference only through a versioned provider contract.
- AGPL/GPL code must not be linked or copied into the proprietary mainline. MinIO is a replaceable external service and still needs a distribution/legal decision before release.

## Engineering rules

- Android first; keep Flutter platform-neutral where practical.
- Offline state is explicit. Never show a count before the server returns a real result.
- Upload follows create package -> blobs -> manifest -> commit and is idempotent at every step.
- Exact duplicate images are rejected by organization-scoped SHA-256 uniqueness. Perceptual similarity only creates a review warning.
- Multi-view images are one capture set. Never sum left/center/right results until a validated deduplication provider exists.
- Any media referenced by a confirmed result is locked. Administrative overrides require a reason and an audit event.
- Database changes use Flyway. Do not edit an applied migration; add a new one.
- No real credentials, production data, or model weights in Git.
- The external `agent-base/dataset` research dataset is read-only. Product code may generate an ignored local manifest from it but must not copy its images, labels, hashes, or absolute paths into tracked files, images, Docker contexts, or CI artifacts.

## Verification

- Spring: `mvn test` and `mvn verify` from `services/business-api`.
- Admin: `pnpm lint` and `pnpm build` from `apps/admin-web`.
- Flutter: `flutter analyze`, `flutter test`, and `flutter build apk --debug` from `apps/mobile`.
- Inference: `python -m pytest` from `services/inference-service`.
- Infrastructure: `docker compose config --quiet` from repository root.
