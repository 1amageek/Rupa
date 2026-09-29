# 工学用CAD拡張戦略の事前レビュー

## 位置付け

- 作成日: 2026-09-22。
- 目的: 工学用CADの機能拡張で、既存実装の重複と設計思想からの逸脱を防ぐ。
- 状態: **限定的な設計・コード読解の記録。設計確定、実装開始承認、全機能の対応認定ではない。**
- この文書は設計の正本ではない。以下の正本への参照と、先行する戦略提案の訂正、未解決の判断を所有する。
- 親会話の実装とは別のサイド会話で作成した。既存の `DESIGN.md`、`PROGRESS.md`、ソース、実行中のアプリは変更しない。
- 確認時の作業ツリーには進行中の変更がある。記述は読解時点の観測であり、固定されたリリースの能力表ではない。対象実装が変わった場合は該当する観測を再確認する。

## 要求と範囲

対象は、一般機械部品、回転体、穴・締結部、肉厚を持つケース、配管・ばね、可変断面、歯車・カム、自由曲面、板金、繰り返し構造と、それらの再編集・組立・製造データ受け渡しである。

これは要求分類であり、各機能が未実装だという意味ではない。強度・熱・燃焼等の解析や加工機制御まで自前実装する要求には拡張しない。CAD形状の成立を、機械部品の強度・製造可能性・安全性の証明として扱わない。

## 設計の正本

| 資料 | 確認に使う判断 |
|---|---|
| [System DESIGN](DESIGN.md) | システム境界と設計階層 |
| [CAD/Mesh責務契約](Rupa/CAD_MESH_RESPONSIBILITY_CONTRACT.md) | 製品の位置付け、表現ごとの正本、明示的な表現選択・変換 |
| [状態・プロジェクト契約](Rupa/STATE_AND_PROJECT_CONTRACT.md) | 更新責務、staging、履歴、revision、公開、派生データのlifetime |
| [RupaKit DESIGN](RupaKit/DESIGN.md) | モジュール間の責務と依存 |
| [Swift-CAD DESIGN](swift-CAD/DESIGN.md) | 形状演算、参照、評価、表示メッシュの契約 |
| [CADDomain DESIGN](RupaKit/Sources/RupaCADDomain/DESIGN.md) | 意味付き操作、バージョン、lowering、登録集合 |
| [Topology Editing DESIGN](RupaKit/Sources/RupaCore/TopologyEditing/DESIGN.md) | 現在の辺・シート編集の対応範囲とトランザクション境界 |

正本間の矛盾が判断を変える場合は、都合よく解釈して実装で埋めず、該当する判断を保留する。

## 確認済みの観測と戦略への影響

「設計契約」「実装読解」「テスト読解」を区別する。以下に今回の実行検証による証拠はない。

| ID | 観測と根拠 | 種別 | 戦略への影響 |
|---|---|---|---|
| F1 | 製品はAgent-ready direct-modeling CADで、Authored Meshも第一級の編集対象。[責務契約](Rupa/CAD_MESH_RESPONSIBILITY_CONTRACT.md) | 設計契約 | 履歴操作中心の別製品へ暗黙に転換しない。寸法・拘束は直接編集を支えるものとして整合を確認する |
| F2 | Product、CAD、Authored Meshは意味ごとの正本を持ち、同一Objectに複数表現を保持できる。[責務契約](Rupa/CAD_MESH_RESPONSIBILITY_CONTRACT.md) | 設計契約 | 単一のCAD→Meshパイプラインへ全ソースを統合しない |
| F3 | 部品定義は既存Scene参照を検証し、配置は定義参照・変換を保持してSceneへ登録する。[DesignDocument+Component](RupaKit/Sources/RupaCore/DesignDocument+Component.swift) | 実装読解 | 部品定義・配置モデルを新設しない。機構拘束等の不足は別途確認する |
| F4 | Agentの部品配置lowererは既存の `.createComponentInstance` へ変換する。[ComponentInstantiateLowerer](RupaKit/Sources/RupaCADDomain/ComponentInstantiateLowerer.swift) | 実装読解 | 別の共通コマンド基盤を追加せず、既存の合流先を使う |
| F5 | CAD評価にはキャッシュ照合、同一revision結果の再利用、前回評価を渡す再評価がある。[CADGeometrySourceProvider](RupaKit/Sources/RupaCADIntegration/CADGeometrySourceProvider.swift) | 実装読解 | 増分評価を新設するのではなく、既存の無効化条件・再利用範囲を確認する |
| F6 | 文書名変更後にfeature再構築と再テセレーションがゼロになることを検査するテストがある。[IncrementalEvaluationIntegrationTests](RupaKit/Tests/RupaCoreTests/IncrementalEvaluationIntegrationTests.swift) | テスト読解・未実行 | メタデータ変更の限定された検証意図。全操作の性能や実行成功の証拠にはしない |
| F7 | Shellは厚さと選択を解決し、形状を縫合・置換して体積レベルで検証する。除去面は1面に制限される。[ShellFeatureEvaluator](swift-CAD/Sources/CADModeling/ShellFeatureEvaluator.swift) | 実装読解 | 未実装扱いして作り直さず、UI接続・形状対応範囲・実動を分けて調べる |
| F8 | 辺編集とシート編集は選択解決とトランザクション生成を共有する。[DesignDocument+TopologyEditing](RupaKit/Sources/RupaCore/TopologyEditing/DesignDocument+TopologyEditing.swift) | 実装読解 | 別の選択解決や更新経路を追加しない。staging後の成功は別途立証する |
| F9 | シートExtendは既存曲面領域内のトリム拡張であり、一般的な曲面外挿ではない。[Topology Editing DESIGN](RupaKit/Sources/RupaCore/TopologyEditing/DESIGN.md) | 設計契約 | 名前だけで曲面延長の要求が満たされたと判定しない |

## 先行戦略の訂正

| 先行提案 | 訂正 |
|---|---|
| 再編集基盤、部品定義・配置、増分評価を順番に搭載する | 既存実装を前提に、不足する契約・対応範囲だけを特定する |
| 設計ソース→B-rep→Meshを全体像とする | CADの経路だけを表す図だった。Authored Mesh、外部表現、purpose selectionを省略した全体設計にはしない |
| UIとAgentを共通化する | 入口を一つに書き換える意味ではない。既存のCore操作とProjectの更新責務へ合流させる |
| カーネル交換・複数カーネル化を選択肢に置く | 要求を満たせない具体例と原因が未確認のため保留。Swift-CADの責務は形状計算だけではない |
| 作業環境をパーツ・曲面・板金・組立・図面に分ける | UI構成案に留める。別文書モデルや別の更新ownerを導入する承認ではない |
| 全体ロードマップを実装順として提示する | 能力分類としてのみ保持する。依存関係と既存実装の不足を確認するまで実装計画へ転記しない |

## 拡張判断の手順

```text
必要なユーザー操作と完了条件
    ↓
既存の入口 → Core → Swift-CAD → 評価・確定 → 保存を追跡
    ↓
不足を分類
    ├─ 要求を満たす既存経路       → 再利用
    ├─ 既存機能へUI等から届かない → 接続
    ├─ 対応形状や条件が足りない   → 既存ownerで拡張
    └─ 意味・契約自体が存在しない → 所有層を決めて追加
    ↓
影響する設計契約を更新
    ↓
要求に必要な成功・失敗・再編集・保存の振る舞いを検証
```

新しい型、モジュール、レジストリ、キャッシュ、更新ownerを提案する前に、既存の仕組みでは担えない理由を特定する。宣言やファイル名の存在だけで再利用可能とも、未対応とも判定しない。

UIとAgentの共通化は、既存の境界に沿って評価する。

```text
UI intent ───────────────────────────┐
                                    ↓
Agent → semantic operation → lowerer → Core command
                                    ↓
                     Project staging / evaluation / publication
```

これは責務の要約であり、全UI操作・全Agent操作の経路を検証した図ではない。新しいAgent操作は既存のバージョン・登録集合・公開出力契約への変更として扱う。

## 未確認事項と判断に必要な証拠

| 判断対象 | 必要な確認 | 現時点で主張しないこと |
|---|---|---|
| 一般機械加工 | 操作ごとのUI、Core dispatch、具象evaluator、対応形状、失敗、保存を追跡 | 穴・溝・シェル・抜き勾配等が全面対応／全面未対応である |
| 曲線・曲面 | Sweep、Loft、trim、match、offset、thickenの実際の幾何契約と成功範囲 | API名が要求する連続性・誤差保証を満たす |
| 参照と再編集 | 上流変更後の参照解決、曖昧性、失敗時の保持、下流再評価を実動確認 | 安定参照の存在だけで変更耐性が完成している |
| 組立 | 既存definition/instance更新、拘束・自由度・ジョイントの経路を確認 | 部品配置ができることは機構が解けることと同じである |
| 板金 | 専用ソース、曲げ条件、展開との対応、保存経路の有無を確認 | 薄いSolidが作れるため板金設計に対応している |
| 交換・図面 | 実reader/writer、対応entity、単位・配置・形状の往復確認 | STEP等のファイル出力だけで製造受け渡しが成立する |
| 性能 | 対象機器・モデル規模・操作を固定し、既存評価と表示経路を計測 | 増分評価の存在だけで低遅延である |
| カーネル選択 | 既存経路が失敗する要求内の具体例と原因、拡張コスト、契約への影響 | 交換が必要、または現行カーネルだけで全要求を満たせる |

これらは未解決の判断一覧であり、親会話の作業項目へ追加したものではない。次の調査は、着手する要求の判断を変える項目に限定する。

## 実装計画へ進める条件

各変更について、要求、既存owner、実行経路、再利用箇所、不足、変更する契約、失敗条件、完了証拠を対応付ける。既存資料で追跡できる内容は複製しない。

- 既存で成立する部分と追加が必要な部分が分離されている。
- 正本の責務・所有権・表現モデルに未解決の矛盾がない。
- 下位の対応範囲を超える成功をUIやAgentが報告しない。
- 作成だけでなく、対象変更に必要な再編集・失敗・Undo・保存の確認範囲が決まっている。
- 性能の問題は既存の実行経路と測定に結び付いている。

この文書の作成によって、上記条件が満たされたとは扱わない。
