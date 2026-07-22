# Meta Analysis

## Correction: preservation is not P0 completion

The earlier analysis incorrectly promoted recoverability and dependency
determinism from prerequisites into the definition of P0 completion. The
checkpoint and baseline commits protect work and make comparison reproducible,
but they do not complete the product or kernel goals.

The authoritative goal has three connected scopes:

1. Swift-CAD completion remains binary: all public contracts are inventoried,
   every capability is fully supported over its valid public domain, and gates
   G0 through G7 pass on one clean source revision.
2. Rupa CAD-quality P0 requires robust filleting/blending, powerful exact
   booleans, and direct face/edge/vertex manipulation through stable selection,
   source-owned edits, typed diagnostics, undo/redo, viewport, Automation, and
   Agent paths.
3. Rupa product P0 also keeps full CLI workflows, the Universal CAD model, and
   domain-foundation integration open until their documented remaining routes
   and input contracts are implemented and verified.

The old `PersistentName` integration tuple is therefore a diagnostic and
recovery baseline only. It is not the forward target. Forward implementation
must finish the stable-subshape and explicit-tolerance contracts, migrate Rupa
to them, close the exact geometry/topology/modeling failures, and produce the
same-revision evidence required by the normative completion documents.

## Core finding

P0の対象は「巨大な未コミット差分」ではない。次の4世代が同じローカル依存経路に重なっている状態である。

| Generation | Revision | Selection / evaluation contract | Evidence |
|---|---|---|---|
| G0 | swift-CAD `35ffd6e` | `PersistentName`, `.topology`, legacy generated names | Rupa HEAD + OpenUSD `998e505`でbuild成功、旧selection test 1/1 pass |
| G1 | `1060739` | `.subshape(SubshapeID)` | Rupa HEADは`.topology`欠落でcompile failure |
| G2 | `a875eeb` | `StableSubshapeReference`, explicit tolerance, exact architecture | SwiftCAD facade build成功、CADGeometry 9 tests failed |
| G3 | current worktree | certified implicit geometry、exact volume、catalog split等 | CADGeometry 18 failed、CADKernel 48 failed、445 dirty entries |

## Why the current tree is not one atomic commit

- `KernelCapabilities.swift`のtracked削除は、11個のuntracked extensionとuntracked CI checkerを必要とする。
- certified geometryはTopology、Modeling、Kernel、Exchangeの順に下流契約を変える。
- rational B-spline canonicalizationは型削除と多数のcaller/test変更を同時に必要とする。
- 186 untracked filesは合計52,885行であり、tracked差分だけの保存は再現不能になる。

## Contract consequences

Stable selectionへの移行は互換shimの追加だけでは完了しない。RupaKitはSwiftCAD型を境界で広くre-exportし、`PersistentName`参照が520箇所、SwiftCAD importがsource 310 files / test 153 filesに存在する。selection persistence、material binding、measurement、UI、generated body resolutionを一つの移行として扱う必要がある。

## Preservation prerequisites completed

The following preservation prerequisites were completed before resuming the
unfinished implementation. They are not product completion gates.

1. G3を欠落なく回復可能なcheckpointとして保存する。ただしstableやintegration-readyとは呼ばない。
2. G0の3-repository tupleをRupa integration baselineとしてmanifest化する。
3. G1/G2/G3を混ぜず、8つのatomic implementation clusterに分解する。
4. 各clusterに必要なtracked/untracked closure、対象test、既知failureを記録する。
5. RupaKitのlocal path dependencyが、未指定のdirty worktreeを暗黙参照しない状態にする。

## Executed preservation

- Swift-CAD G3 was preserved on `codex/p0-swift-cad-checkpoint` at `288d5cd`.
- The Rupa typed mesh-selection slice was committed at `03e341d`.
- The mesh-selection tests were executed against the G0 dependency tuple: 2 total, 2 passed.
- `P0_INTEGRATION_BASELINE.json` and its checker make the three-repository dependency state explicit.

## Limitations

- G0ではRupaKit全体buildと旧generated-topology selectionの代表テスト1件を確認したが、全RupaKit testは実行していない。
- G2で確認した履歴baselineはCADGeometryのみであり、全kernel testは未実行。
- 現行の失敗66件は原因クラスタまで分類したが、個々の修正方針はP0後の実装計画対象である。
- G3 checkpointは保存用であり、66件の既知failureを解消していない。
