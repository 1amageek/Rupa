# Project Geometry Exchange

## Purpose and Scope

This component belongs to [RupaKit](../DESIGN.md) and has no children. It owns
STEP/STL/OBJ import adaptation to one existing Project source transaction.
Export reads one immutable snapshot and never publishes project state.

## Responsibilities and Boundaries

The App owns panels and security-scoped URL lifetime. CADIntegration parses
bounded input and returns immutable exact CAD or Mesh values. This component
maps those values to existing Core commands; Project owns validation,
evaluation, publication, persistence and history. No file path enters source
provenance and import does not replace the current .rupa file association.

## Related Designs

| Design | Relationship | Contract Used | Summary | Cautions |
|---|---|---|---|---|
| [RupaKit](../DESIGN.md) | parent | Workspace.perform | One source publication and postcommit no-retry outcome | Never replay after publication. |
| [CADIntegration](../../RupaCADIntegration/DESIGN.md) | depends on | Exact import, units, bounded Mesh conversion | Owns native format adaptation | No Core or App dependency. |
| [Core](../../RupaCore/DESIGN.md) | depends on | appendFeatureGraph, importAuthoredMesh | Owns persistent identities and source validity | One staged transaction for all imported bodies. |
| [App](../../../../Rupa/Rupa/Rupa/DESIGN.md) | used by | Operation sequencing and file access | Owns UI and URL lifetime | Scope stays open until detached work finishes. |

## Architecture

```text
App URL + explicit unit for unmarked input
  -> detached CADIntegration import -> immutable source values
  -> Core commands + captured project coordinates
  -> Workspace.perform -> Project commit -> one Undo entry
```

## Contracts and Invariants

- STL/OBJ export uses visible, presentation-selected geometry at the document's
  configured fidelity, not GPU buffers. World placement is baked into positions;
  reflected placement reverses winding. OBJ preserves known dense vertex normals
  and UVs and refuses attributes or materials the native writer cannot preserve.
  Inverse-transpose normals are normalized with a max-component rescale and a
  dimensionless nonzero threshold, so valid scale does not depend on the
  document's length tolerance; nonfinite and zero covectors remain typed
  failures.
  STL is explicitly geometry-only. Empty geometry is an error.
- STEP uses the existing exact source writer only when visible, identity-placed
  CAD occurrences cover every exact body once. Mesh authority, hidden bodies,
  nonidentity placement and duplicate occurrence require another format and are
  typed refusals, never silently dropped geometry.
- The optional CAD interaction cache is not an export prerequisite. STEP uses
  Core's existing exact evaluation resolver with the frozen document and its
  generation: reuse a matching context, otherwise evaluate exact topology only
  off MainActor. This does not create a project publication or a second cache.
- Mesh export conversion charges derived positions, normals, UVs and indices,
  plus the existing vertex-index and face-triangulation scratch, before allocation
  against the existing standard evaluation byte ceiling. Format writers retain
  their bounded byte/entity/time contracts.
- The App owns the destination URL. Encoding runs off MainActor into the native
  bounded sink. Cancellation is checked before `Data.write(.atomic)`, the final
  non-cancellable publication point. Once writing starts it reports its actual
  success/failure; cancellation does not claim to roll back a published file.

- Import appends all bodies atomically; malformed, unsupported, stale or
  cancelled input publishes none. Empty success and partial import are refused.
- STEP geometry is exact and normalized by the native reader. Each body has
  one source feature; its embedded source units survive append without changing
  the current project's display units or expression interpretation.
- Product properties retain qualified format, resolved unit and content digest
  for imported CAD. Authored Mesh retains the adapter's ContentIdentity.
- File parsing, source conversion and command preparation run outside MainActor.
  No new evaluator, cache, mutable document owner or command interpreter is added.

## State, Ownership, and Lifecycle

The Workspace method captures one immutable view and owns one invocation-local
detached task. Cancellation is forwarded and awaited before returning, keeping
the App's file access alive. Project checks captured coordinates before commit.

## Failure, Concurrency, and Constraints

Native format limits and CADIntegration admission apply before allocation.
Workspace preserves typed precommit errors and postcommit no-retry errors.
Concurrent project mutation invalidates the prepared transaction; it is not
silently rebuilt against newer state.

## Verification and Change Impact

RupaKitTests verifies actual import, multiple bodies, exact dimensions and units,
preview/publication isolation, one-step undo/redo, malformed input and stale
transactions. App tests own panel routing and security-scope lifetime. Changes
to Core source commands or native imported feature identities recheck this path.
