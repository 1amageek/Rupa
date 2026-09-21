# Progress

- [x] S1 Product hierarchy lifecycle (group, ungroup, delete) reachable from the workspace. Commit b700eade. `depends:none` `parallel:none`
- [x] S2 Editor commands reachable from the workspace menus and keys: Escape unwinding, selection scope keys, the Tools menu with per-tool prompts, and the answered construction plane key. Commit c3e35355. `depends:S1` `parallel:none`
- [x] S3 What the workspace says reaches the screen, and the canvas stops carrying build notes. Commit 8f6b2fa1. `depends:S1` `parallel:none`
- [x] S4 Workspace chrome: one canvas header above the canvas, and the inspector spends its width on the inspector. Commits 9ef80a92, 11c870bd, f483c413. `depends:S1` `parallel:none`
- [ ] S5 Viewport interaction contract on RealityViewport `depends:S1,S3` `parallel:none`
  - [x] S5.5 Middle mouse orbit, and the keyboard left alone while a field is editing `depends:none` `parallel:none`
  - [ ] S5.2 Drag threshold, drag preview origin, and Escape cancellation `depends:none` `parallel:none`
  - [ ] S5.3 Gizmo follows the body and the sketch it moves, proved behaviourally for the sketch `depends:none` `parallel:none`
  - [ ] S5.4 Hover resolution while the pointer moves, and honest axis triad targets `depends:none` `parallel:none`
  - [ ] S5.1 Verification that one affordance-to-command commit path serves every builder `depends:none` `parallel:none`
- [x] S7 Object parameters the Inspector offers reach the canvas. Commits 3900f5cb..85197f92. `depends:S1` `parallel:none`
- [ ] S6 Integration verification of the whole workspace `depends:S1,S2,S3,S4,S5,S7` `parallel:none`
- [x] S8 Remove unused drawing projection exporters and CLI response fields `depends:none` `parallel:none`
- [x] S9 Remove facade/preview targets and consolidate UI display helpers. Commit pending. `depends:S8` `parallel:none`
- [ ] S10 Consolidate duplicated solid direct-edit processing and expression resolution `depends:S9` `parallel:none`
- [ ] S11 Remove benchmark/responsiveness/performance-only targets from RupaKit `depends:S10` `parallel:none`
- [ ] S12 Update package design and architecture boundary tests for removed targets `depends:S11` `parallel:none`
- [ ] S13 Run focused and package integration verification `depends:S12` `parallel:none`
