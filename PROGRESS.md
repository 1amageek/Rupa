# Progress

- [x] RR-1 (completed subitems: RR-1.1, RR-1.2) outer `7c18df41f384d60e5a4334b4b670039591b1e812` + tracked dirty Agent 差分、nested `52c838be52832e49fc93a136eaf4a99ecf871a7f` を固定して応答性修正をレビューした `depends:none` `parallel:none`
- [x] RR-2 既報契約を fixed / remaining に分類し、到達可能な反例と検証限界を確定した `depends:RR-1` `parallel:none`
- [x] RFX-1 nested Swift-CAD と outer Rupa の corrective path を、exact-source authority、all-or-nothing failure、bounded resource、matching lifecycle、render/picking consistencyまで実装・検証・designer承認した。nested commit `db8b801`、outer commits `42365700` / `a453e38d` `depends:RR-2` `parallel:none`
- [ ] RFX-6 nested/outer exact commitsを統合し、ユーザーが開いているprojectを置換・変更・保存せず、独立検証projectまたは既存標準fixtureで実App・視覚・resource・cancellation・Agent authorityを立証する `depends:RFX-1` `parallel:none`
  - [x] RFX-6.1 affected Swift-CAD/RupaKit testsを固定snapshot・timeout付きで一度通し、直前review済みAgent隔離/lease testsを統合前提として再実行し、Package.resolved・`DesignDocument+Surface.swift`・既存`RupaKit/PROGRESS.md`・scheme-only変更ほかuser変更がtask commitへ混入していないことを確認する `depends:RFX-1` `parallel:none`
  - [ ] RFX-6.2 signed Release Rupaを独立fixtureで起動し、同一Agent API/workspace authorityからsurface shading/contoursとpicking、UI/run-loop、10-run frame/memory/cancellation、capability/status、typed failureを実経路で確認する。save/restartは検証projectだけへ行う。部分証拠: outer `a453e38d`のsourceから変更なくRelease build exit 0（`/tmp/rupa-final-signed-release-build.log`）、`team.stamp.Rupa` / team `WWCKBW8CKN`の署名を`--deep --strict`で検証済み。Mac unlock待ちでrunning Appは置換せず、live経路は未検証 `depends:RFX-6.1` `parallel:none`
  - [ ] RFX-6.3 branch/upstreamとtask外unpushed commitを確認し、root progressと再現可能な証拠をouter最終commitへ含める。outerはupstreamなし、nestedはtask外の未push commitを8件含むためpushしない。tag/release/deployは行わない `depends:RFX-6.2` `parallel:none`
