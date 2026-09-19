# Analysis Brief

- Question: Can Agent manipulate all Rupa data, allowing Rupa to operate primarily as a viewer?
- Scope: Current root worktree, Rupa app host, RupaKit Agent protocol/runtime/automation/core paths, and relevant tests.
- Decision standard: “All operations” requires live connection, discovery, read, mutation, undo/redo, file/session lifecycle, persistence, and success/failure behavior verification.
- Non-goals: No implementation changes, deployment, or destructive actions.
- As of: 2026-07-27T22:13:00+09:00
