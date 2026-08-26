# Progress

- [x] T06A-1 read and interaction contract (commit: Define project read and interaction boundary) `depends:none` `parallel:none`
- [x] T06A-2 MeshSource-native Viewport (commit: Add MeshSource-native viewport presentation boundary) `depends:T06A-1` `parallel:none`
- [x] T06A-3 ProjectWorkspace command parity (commit: Define ProjectWorkspace command boundary) `depends:T06A-1` `parallel:none`
- [x] T06A-4 MainView cutover (commit: Cut MainView over to ProjectWorkspace) `depends:T06A-2,T06A-3` `parallel:none`
- [x] T06A-5 Agent production registration cutover (commit: Cut Agent over to ProjectWorkspace) `depends:T06A-3,T06A-4` `parallel:none`
- [ ] T06A-6 ApplicationRoot file and history integration `depends:T06A-4,T06A-5` `parallel:none`
  - [ ] T06A-6.1 Compose exactly one ProjectController and one MainActor ProjectWorkspace at ApplicationRoot and publish an evaluated initial view or visible typed launch failure `depends:T06A-4,T06A-5` `parallel:none`
  - [ ] T06A-6.2 Route production undo, redo, load, and save through ProjectWorkspace with explicit URL ownership, cancellation, dirty state, stale publication, and failure presentation `depends:T06A-6.1` `parallel:none`
  - [ ] T06A-6.3 Prove the actual app route can display, select, navigate, mutate, undo, redo, save, load, and redisplay CAD-only, Mesh-only, and mixed projects `depends:T06A-6.2` `parallel:none`
  - [ ] T06A-6.4 Audit app entry points, package dependencies, previews, tests, and source references so no production branch selects the legacy EditorSession route `depends:T06A-6.3` `parallel:none`
  - [ ] T06A-6.5 Pass task-designer review, focused app verification, and commit the reviewed production integration `depends:T06A-6.4` `parallel:none`
- [ ] T06A-IV integration verification `depends:T06A-1,T06A-2,T06A-3,T06A-4,T06A-5,T06A-6` `parallel:none`
  - [ ] T06A-IV.1 Verify the real ApplicationRoot-to-ProjectController-to-ProjectWorkspace-to-MainView-to-Viewport success and failure paths for CAD-only, Mesh-only, and mixed projects `depends:T06A-1,T06A-2,T06A-3,T06A-4,T06A-5,T06A-6` `parallel:none`
  - [ ] T06A-IV.2 Re-run command parity, source authority, revision, cancellation, rollback, late publication, package integrity, zero-copy, copy telemetry, and UI-Agent interleaving evidence `depends:T06A-IV.1` `parallel:none`
  - [ ] T06A-IV.3 Re-run incomplete-implementation, synchronization, ownership, unsafe-memory, target-branch, production-entry, and legacy-route audits and reject structure-only evidence `depends:T06A-IV.2` `parallel:none`
  - [ ] T06A-IV.4 Synchronize normative architecture and state-contract documents, remove obsolete production-route claims, pass final task-designer review, and commit integrated evidence `depends:T06A-IV.3` `parallel:none`
