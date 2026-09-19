# Progress

- [x] S1 Product hierarchy lifecycle (group, ungroup, delete) reachable from the workspace. Commit b700eade. `depends:none` `parallel:none`
- [x] S2 Editor commands reachable from the workspace menus and keys: Escape unwinding, selection scope keys, the Tools menu with per-tool prompts, and the answered construction plane key. Commit c3e35355. `depends:S1` `parallel:none`
- [x] S3 What the workspace says reaches the screen, and the canvas stops carrying build notes. Commit 8f6b2fa1. `depends:S1` `parallel:none`
- [ ] S4 Workspace chrome: inspector width, folded rail, header and status line `depends:S1` `parallel:none`
  - [ ] S4.1 Inspector keeps a fixed pane width `depends:none` `parallel:none`
  - [ ] S4.2 Folded utility rail keeps its functions `depends:none` `parallel:s4-chrome`
  - [ ] S4.3 Canvas header with pointer-time control descriptions `depends:none` `parallel:s4-chrome`
- [ ] S5 Viewport interaction contract on RealityViewport `depends:S1,S3` `parallel:none`
  - [ ] S5.1 One affordance-to-command commit path replacing per-builder rederivation `depends:none` `parallel:none`
  - [ ] S5.2 Drag threshold, drag preview origin, and Escape cancellation `depends:S5.1` `parallel:none`
  - [ ] S5.3 Gizmo follows the body and the sketch it moves `depends:S5.1` `parallel:none`
  - [ ] S5.4 Hover resolution while the pointer moves, and honest axis triad targets `depends:S5.1` `parallel:none`
  - [ ] S5.5 Middle mouse orbit and keyboard focus release during edits `depends:S5.1` `parallel:none`
- [ ] S6 Integration verification of the whole workspace `depends:S1,S2,S3,S4,S5` `parallel:none`
