# Progress

- [x] S1 Product hierarchy lifecycle (group, ungroup, delete) reachable from the workspace. Commit b700eade. `depends:none` `parallel:none`
- [x] S2 Editor commands reachable from the workspace menus and keys: Escape unwinding, selection scope keys, the Tools menu with per-tool prompts, and the answered construction plane key. Commit c3e35355. `depends:S1` `parallel:none`
- [x] S3 What the workspace says reaches the screen, and the canvas stops carrying build notes. Commit 8f6b2fa1. `depends:S1` `parallel:none`
- [ ] S4 Workspace chrome: one canvas header above the canvas, and the inspector spends its width on the inspector `depends:S1` `parallel:none`
  - [x] S4.1 Inspector content fills the pane it is given `depends:none` `parallel:none`
  - [x] S4.2 One canvas header bar above the canvas; the floating rail and the chip row are gone `depends:S4.1` `parallel:none`
  - [ ] S4.3 Header controls say what they are the moment they are pointed at `depends:S4.2` `parallel:none`
  - [ ] S4.4 The scale readout moves into the header and the canvas keeps only the axis triad `depends:S4.2` `parallel:none`
- [ ] S5 Viewport interaction contract on RealityViewport `depends:S1,S3` `parallel:none`
  - [ ] S5.1 One affordance-to-command commit path replacing per-builder rederivation `depends:none` `parallel:none`
  - [ ] S5.2 Drag threshold, drag preview origin, and Escape cancellation `depends:S5.1` `parallel:none`
  - [ ] S5.3 Gizmo follows the body and the sketch it moves `depends:S5.1` `parallel:none`
  - [ ] S5.4 Hover resolution while the pointer moves, and honest axis triad targets `depends:S5.1` `parallel:none`
  - [ ] S5.5 Middle mouse orbit and keyboard focus release during edits `depends:S5.1` `parallel:none`
- [x] S7 Object parameters the Inspector offers reach the canvas. Commit 85197f92. `depends:S1` `parallel:none`
- [ ] S6 Integration verification of the whole workspace `depends:S1,S2,S3,S4,S5,S7` `parallel:none`
