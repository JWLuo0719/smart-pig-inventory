## Research model release boundary

- `test-assets/generated/` contains ignored local evidence only. Never force-add its regression summaries, release manifests, baselines, images, or rehearsal reports.
- A new weight, threshold, image size, IoU, runtime, or adapter version requires a fresh full val/test regression, a new research release manifest, comparison with an explicitly selected immutable baseline, and an isolated rollback rehearsal. Use `scripts/run-team-yolo-regression.ps1`, `scripts/model_release_gate.py`, and `scripts/run-model-rollback-rehearsal.ps1`.
- Never replace a regression baseline automatically. A model identity or selected-threshold change must fail the old baseline gate and create a new versioned candidate; the test split must not be used to tune the threshold.
- Research manifests must remain `research_candidate` with `model_approved=false`, automatic counting and multiview aggregation disabled, manual review required, and license/business-gold-set/owner approval pending until those decisions are explicitly supplied.
- Fault and rollback tests may run only in their fixed isolated Compose projects: `pig-inventory-p1-fault` and `pig-inventory-p1-rollback`. Never repoint them at `pig-inventory-p0`, and never reset or delete P0 volumes as part of a test.
