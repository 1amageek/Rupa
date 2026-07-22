# Analysis Log

## 2026-07-22

- Root、swift-CAD、swift-OpenUSDのGit state、history、reflog、local path dependencyを確認。
- `skltn`で980 Swift filesをindexし、46 parser diagnosticsを高リスク探索信号として扱った。
- Package.swift、SPEC、ROADMAP、capability ledger、DocumentEvaluator、DocumentEvaluationEngine、selection/lineage/index contractsの原文を確認。
- RupaKitのSwiftCAD importとlegacy contract参照を集計。
- 現行CADGeometry-Testsを実行: 242 total / 224 passed / 18 failed。
- 現行CADKernel-Testsを実行: 464 total / 416 passed / 48 failed。
- `a875eeb`をisolated worktreeで検証: SwiftCAD facade build succeeded、CADGeometry 9 unique failing tests。
- Rupa HEAD + swift-CAD `1060739`: `.topology` API mismatchでbuild failed。
- Rupa HEAD + swift-CAD `35ffd6e` + current OpenUSD: `USDError` exhaustiveness mismatchでbuild failed。
- OpenUSD historyを追跡し、typed error expansion前の`998e505`を特定。
- Rupa `4d90a4b` + swift-CAD `35ffd6e` + swift-OpenUSD `998e505`: full RupaKit package build succeeded。
- 同tupleで`generatedTopologySelectionResolverRoundTripsRectangleFacesAndCornerEdges()`を実行: xcresult 1 total / 1 passed。
- 誤ったsuite filterで0 testsとなったrunは証拠から除外。
- 一時worktreeはすべてGit worktree removeで削除され、元worktreeのみ残存することを確認。
- Swift-CAD `codex/p0-swift-cad-checkpoint`を作成し、complete WIP closureを`288d5cd`としてcommit。
- Rupa `codex/p0-integration-baseline`を作成し、typed mesh-selection sliceを`03e341d`としてcommit。
- Rupa `03e341d` + swift-CAD `35ffd6e` + swift-OpenUSD `998e505`で追加selection testsを実行: xcresult 2 total / 2 passed。
- 3-repository baseline manifest、decision record、revision/cleanliness checkerを追加。
