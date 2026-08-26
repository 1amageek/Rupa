# Progress

- [x] T06A-1 read and interaction contract (commit: Define project read and interaction boundary) `depends:none` `parallel:none`
- [x] T06A-2 MeshSource-native Viewport (commit: Add MeshSource-native viewport presentation boundary) `depends:T06A-1` `parallel:none`
- [x] T06A-3 ProjectWorkspace command parity (commit: Define ProjectWorkspace command boundary) `depends:T06A-1` `parallel:none`
- [x] T06A-4 MainView cutover (commit: Cut MainView over to ProjectWorkspace) `depends:T06A-2,T06A-3` `parallel:none`
- [x] T06A-5 Agent production registration cutover (commit: Cut Agent over to ProjectWorkspace) `depends:T06A-3,T06A-4` `parallel:none`
- [x] T06A-6 ApplicationRoot file and history integration (commit: Integrate application project lifecycle) `depends:T06A-4,T06A-5` `parallel:none`
- [ ] T06A-IV integration verification `depends:T06A-1,T06A-2,T06A-3,T06A-4,T06A-5,T06A-6` `parallel:none`
  - [ ] T06A-IV.1 Verify the real ApplicationRoot-to-ProjectController-to-ProjectWorkspace-to-MainView-to-Viewport success and failure paths for CAD-only, Mesh-only, and mixed projects `depends:T06A-1,T06A-2,T06A-3,T06A-4,T06A-5,T06A-6` `parallel:none`
  - [ ] T06A-IV.2 Re-run command parity, source authority, revision, cancellation, rollback, late publication, package integrity, zero-copy, copy telemetry, and UI-Agent interleaving evidence `depends:T06A-IV.1` `parallel:none`
  - [ ] T06A-IV.3 Re-run incomplete-implementation, synchronization, ownership, unsafe-memory, target-branch, production-entry, and legacy-route audits and reject structure-only evidence `depends:T06A-IV.2` `parallel:none`
  - [ ] T06A-IV.4 Synchronize normative architecture and state-contract documents, remove obsolete production-route claims, pass final task-designer review, and commit integrated evidence `depends:T06A-IV.3` `parallel:none`
