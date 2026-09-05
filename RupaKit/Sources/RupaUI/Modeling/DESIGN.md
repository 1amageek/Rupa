# Modeling UI

## Purpose and Scope

This component is a child of [RupaUI](../DESIGN.md), with no children. It owns
the editable CAD and Mesh operation forms and their transient preview state,
not source editing or kernel algorithms.

## Responsibilities and Boundaries

The draft retains user text, units, ordered selection and operation options.
Planning produces existing `EditorCommand` values. Workspace remains the only
mutation entry point. Invalid text remains editable and produces a visible
typed error, never a default successful command. MainView owns task sequencing
and passes preview/apply/cancel callbacks; this component owns no task or cache.

## Related Designs

| Design | Relationship | Contract Used | Summary | Cautions |
|---|---|---|---|---|
| [RupaUI](../DESIGN.md) | parent | Snapshot presentation and Workspace intent | Composes the form. | Never write a document from a view. |
| [RupaCore](../../RupaCore/DESIGN.md) | depends on | EditorCommand validation and source operations | Owns CAD semantics and topology references. | Scene occurrence transforms are not feature geometry. |
| [RupaKit](../../RupaKit/DESIGN.md) | used by parent | Exact preview/commit | Owns publication coordinates. | A preview does not grant commit authority. |

## Architecture

```text
Ordered selection + text fields -> ModelingOperationDraft -> EditorCommand
                                                              |
MainView callbacks -> Workspace preview -> derived preview display
                   -> Workspace perform -> one source commit + Undo
Cancel -> discard draft and preview, no source mutation
```

The parent keeps a single cancellable task and a value-only preview state.
A new draft invalidates the previous token; late completions cannot restore it.
Taking a ready request for Apply consumes it before awaiting publication, so
repeated button events cannot commit twice. Source or selection publication
invalidates a prepared request; Workspace still validates its exact coordinates.
Preview geometry is displayed in the existing Viewport with supplied-only
evaluation and no source-edit callbacks. Cancel never rolls back an already
published transaction; post-commit errors retain the existing no-replay contract.

Mesh drafts hold persistent source element IDs, a source handle and explicit
source-coordinate lengths. They produce existing Mesh edit plans; the Workspace
Mesh adapter owns handle validation and conversion to source transactions. CAD
Make Editable uses the modeling-purpose conversion contract, never a rendered
triangle copy. Selection is tied to a published scene snapshot and is discarded
when that source changes. Rendering exposes actual source vertices, boundary
edges and faces, not triangulation diagonals as editable edges.

MainView builds the immutable selection outline off MainActor only when the
snapshot, occurrence or selected IDs change. SwiftUI task cancellation propagates
to the worker; a cancelled or stale result cannot publish. Canvas only projects
retained points and segments. Outlines use an orange X-ray overlay, with an
explicit truncation count when the display limit is reached; selected IDs are
never truncated. Numeric field edits do not rebuild selection geometry.
Vertex-position prefill consumes the matching overlay's retained local position.
Draft planning bounds the selected-ID count and validates text and operation
domains; source membership validation belongs to Workspace staging off MainActor.

The feature-history section displays the source graph's ordered features.
Suppress/unsuppress and move actions prepare existing source commands, preview
their evaluated candidate and require Apply. Core owns dependency validation;
the UI does not silently move dependent features or suppress a dependency tree.
Named parameter editing remains in the existing document inspector. Selecting a
history row selects its existing scene presentation when available; a suppressed
or unpresented feature remains visible in history without a synthetic scene node.
Each history row presents the feature name, its ordered input/dependency names,
and an explicit suppressed state. Filtering changes visibility only: reorder
commands always carry the complete source graph order and swap adjacent nodes
in that order. Suppression and reorder actions retain the existing preview/apply
path; the row is not a second source graph or a dynamic definition editor.

## Contracts and Invariants

- Box, Cylinder, Sphere, Extrude, Revolve, Sweep, Loft, Boolean, Fillet and Chamfer use existing
  Core commands. Source IDs are allocated by Core, never by this UI component.
- Length text accepts explicit units and otherwise uses the displayed unit;
  angle fields use degrees. All numeric inputs must be finite. Required sizes,
  radii and chamfer distances are positive; a zero revolve angle is rejected.
- The form shows ordered operands and their roles. Loft section order can be
  changed explicitly; Boolean's last operand is the tool. Selection replacement
  is explicit. Authored Mesh cannot masquerade as a CAD feature.
- Feature-only operations reject transformed occurrences, including transformed
  ancestors, instead of ignoring their world placement. Kernel limitations
  remain typed failures from actual preview/evaluation, not successful fallbacks.
- Editing a draft invalidates the parent's previous preview. Apply is enabled
  only for a completed matching preview and while no operation is running.
  Apply and Preview are disabled during work; Cancel remains available.
- The Definitions inspector exposes existing named parameter expressions and
  their dependency/dependent summaries through the existing parameter editor.
  It does not claim that new creation drafts have dynamic expression binding;
  graph authoring remains outside this component until the product choice is
  resolved.

## State, Ownership, and Lifecycle

SwiftUI owns the value draft for one operation. Cancel, document replacement or
successful commit releases it. Published snapshot coordinates are retained by
the parent operation flow, not inferred from draft contents.

## Verification and Change Impact

`Tests/RupaUIPackageTests/ModelingOperationDraftTests.swift` verifies exact
parameter forwarding, operand order, invalid inputs and transformed/non-CAD
selection refusal. Parent integration tests own preview cancellation, stale
completion and exactly-once Apply. Signed App tests own actual controls and
geometry display. The layout reuses native SwiftUI controls and existing
Workspace spacing/semantic colors; no separate web-style design system is added.
Validation includes keyboard labels, disabled/busy/error states, light/dark
appearance and increased contrast at the App boundary.
