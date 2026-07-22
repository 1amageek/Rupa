# P0 Swift-CAD Understanding Brief

## Objective

P0を安全に完了するため、RupaKit・swift-CAD・swift-OpenUSDの実装契約、履歴層、現在の未統合作業、実テスト結果を分離して理解する。

## Decision to support

現在の巨大なswift-CAD作業ツリーを、どの単位で保存・固定・分離すれば、ユーザー変更を失わずにRupaの統合基準を回復できるか。

## Scope

- 3リポジトリのGit履歴とローカル依存関係
- Swift-CADのモジュール構造とDocument evaluation data flow
- tolerance、selection、lineage、generated topology identityの公開契約
- 現在の変更を構成する原子的な実装クラスタ
- 現行・履歴コミット・互換タプルのbuild/test evidence

## Non-goals

- 作業ツリーの変更、コミット、ブランチ作成、巻き戻し
- P1以降のRupa selection migration実装
- 全テストスイートのgreen化

## Evidence standard

宣言や構造だけで実装済みと判定せず、公開APIの原文、呼び出し元、typed failure、実行テスト、xcresult件数を確認する。
