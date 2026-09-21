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

Feature history uses the parent's [sidebar symbol adapter](../DESIGN.md#sidebar-symbols)
for its status and action icons. Active/suppressed meaning, selection, preview
commands, and busy-state admission remain owned by the existing history view.

## Related Designs

| Design | Relationship | Contract Used | Summary | Cautions |
|---|---|---|---|---|
| [RupaUI](../DESIGN.md) | parent | Snapshot presentation and Workspace intent | Composes the form. | Never write a document from a view. |
| [RupaCore](../../RupaCore/DESIGN.md) | depends on | EditorCommand validation, source operations, `WorkspaceScaleDefaults` and `WorkspaceInteractionScaleDefaults` | Owns CAD semantics, topology references and the workspace scale's published defaults. | Scene occurrence transforms are not feature geometry. A default feature size and an interaction step are different quantities. |
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
Both operation panels fill their allocated inspector region; their intrinsic form
height must not shrink the Canvas/inspector split. Each panel contains its child
accessibility elements so Preview, Apply and field identifiers remain distinct.
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

- Primitive entries in the palette and Model menu activate the shared Solid
  canvas tool with a MainView-owned `WorkspaceSolidShape`. Click places a default
  primitive; drag sets its rectangle or radius. Sphere uses the construction
  plane's world center; Cylinder extrudes its local circle along the plane normal
  using the existing workspace depth. Circle footprint previews use the same
  radius defaults and explicit input as planning. Box retains its rectangle and
  profile-extrusion routes. Selection never publishes source; click/release uses
  the existing snapshot-bound Workspace transaction.
- Extrude, Revolve, Loft, Boolean, Fillet and Chamfer are exposed in the palette
  through the existing draft entry point; Sweep retains its canvas route. One
  button renderer owns metrics, colors, selection, accessibility and hover hints.
  Draft forms explain Preview-before-Apply and retain typed operand validation.

- The parent [canvas tool route](../DESIGN.md#canvas-side-tool-routing) launches
  Surface as the existing Loft draft with sheet output enabled. It consumes the
  current ordered profile selection and retains the same preview, Apply, typed
  validation and Cancel lifecycle as other modeling drafts. A Circle Sketch is
  a sketch result and is not exposed under the Surface name.
- Box, Cylinder, Sphere, Extrude, Revolve, Sweep, Loft, Boolean, Fillet and Chamfer use existing
  Core commands. Source IDs are allocated by Core, never by this UI component.
- Length text accepts explicit units and otherwise uses the displayed unit;
  angle fields use degrees. All numeric inputs must be finite; a zero revolve
  angle is rejected. A length that gives a new feature its extent, such as a
  size, a radius or an extrude distance, must exceed the document's own
  distance tolerance, because Core refuses one at or below it, and the refusal
  names that threshold as a readable length. An amount applied to geometry
  that already exists, such as a fillet radius or a chamfer distance, is a
  different quantity: Core asks only that it be positive, so this component
  asks the same and does not invent a stricter threshold it would then refuse
  work for. Core's remaining geometric requirements, such as whether a sketch
  yields a closed profile or whether an edge treatment holds together, stay
  typed failures from the actual preview rather than preconditions restated
  here.
- A new draft opens at the workspace scale's default feature size, which is
  the size the canvas solid tool places, so the panel and the canvas agree on
  what one default solid is at the current scale. The workspace's interaction
  step is the smallest increment the workspace moves by and is not a size: at
  a fine scale it equals the document's distance tolerance, and a solid whose
  side is the tolerance is degenerate. Fillet and chamfer amounts are
  increments applied to an existing edge and keep the step.
  [RupaCore](../../RupaCore/DESIGN.md) owns both defaults; this component only
  chooses which one a kind opens at.
- Extrude, Revolve and Loft operands must be features that output a profile.
  Core resolves those references itself and refuses one that does not, so
  `command(in:)` reads the same output role and refuses first; a press whose
  only outcome is that refusal is then never offered.
- The form shows ordered operands and their roles. Loft section order can be
  changed explicitly; Boolean's last operand is the tool. Selection replacement
  is explicit. Authored Mesh cannot masquerade as a CAD feature.
- Feature-only operations reject transformed occurrences, including transformed
  ancestors, instead of ignoring their world placement. Kernel limitations
  remain typed failures from actual preview/evaluation, not successful fallbacks.
- Editing a draft invalidates the parent's previous preview. Apply is enabled
  only for a completed matching preview and while no operation is running.
  Apply and Preview are disabled during work; Cancel remains available.
- Preview is offered only while the draft names a command. The panel plans the
  draft it is showing against the document it is showing it for, and when that
  plan refuses it disables Preview and displays the reason the plan gave, so a
  press whose only outcome is a refusal is never offered. `command(in:)` stays
  the one place that decides what a draft means; the panel reads its refusal
  rather than restating the preconditions. The reason is a function of the
  draft and the document read while the view is built, not an event, so it is
  displayed and not recorded; the workspace's
  [failure surfacing](../DESIGN.md#failure-surfacing) rule owns that split.
  Planning walks each operand's ancestors by scanning the scene node table, so
  the panel pays that walk once for every evaluation of its body.
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
selection refusal. For every workspace scale preset it also evaluates the
command a newly opened primitive draft names, so a default the kernel would
refuse is a test failure rather than a failure record at run time. It holds
the two thresholds apart by driving both: a size at the document's distance
tolerance names no command, while an edge amount at that same tolerance does
and only a non-positive one is refused. It also holds that an operand
producing no profile is refused before the press, reading the refusal text so
another precondition cannot pass the check for it. Parent
integration tests own preview cancellation, stale completion and
exactly-once Apply. Signed App tests own actual controls and
geometry display. The layout reuses native SwiftUI controls and existing
Workspace spacing/semantic colors; no separate web-style design system is added.
Validation includes keyboard labels, disabled/busy/error states, light/dark
appearance and increased contrast at the App boundary.
