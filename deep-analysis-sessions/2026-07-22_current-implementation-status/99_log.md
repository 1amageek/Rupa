# Analysis Log

- 2026-07-22T09:30+09:00: Inspected root repository structure, Git state, package manifests, status documents, and recent commits.
- 2026-07-22T09:36+09:00: Built `skltn` structural map for RupaKit; recorded 1,230 indexed Swift files and eight parser-diagnostic files. Parser diagnostics were treated as navigation limitations, not compiler failures.
- 2026-07-22T09:38+09:00: Confirmed the active app rendering path still uses `ViewportSceneBuilder`; no production consumer of `UniversalViewportSceneBuilder` was found.
- 2026-07-22T09:39+09:00: Attempted Rupa integration test enumeration; build failed before tests due Swift-CAD/RupaKit API drift.
- 2026-07-22T09:40+09:00: Attempted RupaGeometry tests through the package scheme; package-wide build failed at `CADGeometrySourceProvider` because `DocumentEvaluator` now requires tolerance.
- 2026-07-22T09:40+09:00: Ran full `CADGeometry-Tests` with timeout. Result: 224 passed, 18 failed, 0 skipped, 242 total.
- 2026-07-22T09:43+09:00: Verified that an individually addressed Swift Testing case matched zero tests; did not count the command as success.
- 2026-07-22T09:43+09:00: Ran full `CADKernel-Tests` with timeout. Result: 416 passed, 48 failed, 0 skipped, 464 total; one test exceeded its one-minute allowance.
- 2026-07-22T09:52+09:00: Compared executable evidence with Universal 3D and Swift-CAD roadmaps and formed synthesis.
- 2026-07-22T09:53+09:00: Created report artifacts. Confidence updated: current worktree release readiness 0.15; universal foundation implementation 0.90; app reachability 0.98 verified as incomplete.
- 2026-07-22T10:13+09:00: Generated the final evidence-report HTML and validated all JSON artifacts.
