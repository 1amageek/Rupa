# Analysis Strategy

## Frameworks

1. **Version strata analysis**: API契約が変化したコミット境界を世代として分離する。
2. **Dependency closure analysis**: 変更ファイルを、単独でbuild/test可能な原子的クラスタに束ねる。
3. **Contract and data-flow analysis**: RupaKitからDocumentEvaluator、BRep、SubshapeIndex、selection persistenceまで追跡する。
4. **Evidence triangulation**: Git差分、原文実装、構造スキャン、build、xcresultを相互照合する。
5. **Risk decomposition**: 保存リスク、統合リスク、数値幾何リスク、契約移行リスクを分離する。

## Questions

- 現在のWIPは単一の変更か、複数世代・複数クラスタの積層か。
- RupaKitが最後に利用できるselection契約はどのrevisionか。
- そのrevisionはどのswift-OpenUSD revisionとの組み合わせで実際にbuildできるか。
- 現在のWIPをtracked filesだけで保存できるか。
- P0完了を「実装完了」ではなく、どの回復可能性・再現可能性で定義すべきか。

## Verification plan

- `skltn status/tree/symbol`で構造と高リスク領域を特定後、原文を読む。
- `git diff --stat`, `git log`, `git reflog`, `rg`で変更量・契約参照・依存境界を測る。
- 現行worktreeでCADGeometry/CADKernelを実行する。
- `a875eeb`を隔離worktreeで実行し、現行WIPとの差を分離する。
- Rupa HEADと歴史的swift-CAD/swift-OpenUSDを隔離worktreeで組み合わせ、buildと旧selectionの実テストを確認する。
- 0件実行のテストは成功証拠から除外する。
