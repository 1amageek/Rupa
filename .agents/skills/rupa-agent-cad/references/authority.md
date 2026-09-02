# Live Project Authority

```text
Agent request or live CLI adapter
    -> ProjectAgentCommandController
    -> registered ProjectWorkspace
    -> ProjectController actor
    -> source publication and evaluation
```

`ProjectController` owns source transactions, evaluation, package state, rollback, and publication coordinates. The API request and CLI adapter carry intent; neither is an alternate source authority.

## Session contract

- Resolve exactly one registered live session before mutation.
- Match the requested project identity to the workspace's current project.
- Carry the current document generation and required revision coordinates.
- After publication, discard old coordinates and obtain a new immutable view.
- Treat stale coordinates as a typed failure. Re-read and re-plan as a new intent.
- A lost response after dispatch is outcome-unknown. Inspect current state before any new mutation.

## Source provenance

- A source reference is either a local output of an earlier node in the same
  semantic program or an exact existing identity read from this live session.
- Preserve the discovered source kind and use the corresponding typed
  reference. Do not infer an ID from a name, geometry, ordering, or prior
  session.
- `sourceReferenceUnavailable` is a prepublication planning/provenance error.
  It does not mean that the semantic operation is unsupported and does not
  authorize a fallback operation.

## Authority restrictions

- Do not edit ZIP entries or JSON/blob members inside `.rupa`.
- Do not mutate `EditorSession`, `DesignDocument`, CAD/Mesh storage, or swift-CAD directly from an external Agent workflow.
- Do not use automatic live/file switching or forced file editing for an open project.
- Do not infer mutation success from a viewport screenshot.

## Verification

Read through the registered workspace and verify the invariants relevant to the
operation: receipt source/output bindings, semantic identity, exact source
values and units, topology observations, analytic surface kinds, measurements,
placement and hierarchy, representation selection, publication advancement,
and unchanged state on failure.

Saving is separate and must not precede geometry verification. When persistence
is required, request an explicit save through the application-owned controller
and reload through Rupa before claiming durable completion.

## Source authorities

- `/Users/1amageek/Desktop/3D/RupaKit/Sources/RupaAgentRuntime/ProjectAgentCommandController.swift`
- `/Users/1amageek/Desktop/3D/RupaKit/Sources/RupaKit/ProjectWorkspace.swift`
- `/Users/1amageek/Desktop/3D/RupaKit/Sources/RupaProject/ProjectController.swift`
- `/Users/1amageek/Desktop/3D/RupaKit/Sources/RupaCLIKit/DESIGN.md`
