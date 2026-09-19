# Analysis Log

- 2026-07-12: Initialized the review session.
- 2026-07-12: Confirmed the target repository is clean and isolated the review from unrelated workspace changes.
- 2026-07-12: Ran a repository structural scan; 285 source files were indexed and five parser limitations were reported by the structural scanner.
- 2026-07-12: Read README, philosophy, normative specification, kernel roadmap, package manifest, public facade, feature IR, major evaluators, persistence, exchange, and tests.
- 2026-07-12: Reproduced clean package-resolution failure caused by the sibling swift-OpenUSD path dependency.
- 2026-07-12: Verified the current GitHub Actions run fails SwiftPM and WebAssembly jobs on the same missing dependency; 137 of 140 recorded runs are failures.
- 2026-07-12: Reproduced the CI forbidden-pattern grep and confirmed one lexical false positive plus two real precondition matches.
- 2026-07-12: Counted 618 declared tests, 55,493 source LOC, and 27,879 test LOC. Confirmed current CADCoreTests 21/21 and CADUSDImportTests 4/4 via xcodebuild test-without-building.
- 2026-07-12: Attempted a current focused xcodebuild test twice; the full package build graph timed out before test execution at 30 seconds.
- 2026-07-12: Verified local WebAssembly build succeeds with Swift 6.3.1 and the sibling swift-OpenUSD checkout.
- 2026-07-12: Mapped 20 capability areas, 8 major risks, and 6 ordered recovery actions.
- 2026-07-12: Updated ontology to 45 Factor Nodes and validated it successfully.
- 2026-07-12: Generated the standalone eight-section HTML synthesis report and its evidence-backed visual datasets.
- 2026-07-12: Revalidated every JSON artifact, the 45-node ontology, all local report links, and the rendered report preview. The swift-CAD worktree remained clean.
