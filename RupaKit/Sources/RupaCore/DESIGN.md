# RupaCore Authored Mesh Authority Design

## Purpose and Scope

This module owns the Product document's Authored Mesh source authority and the
Core-side application of a bounded Mesh edit plan. It is a child of the
[RupaKit package design](../../DESIGN.md) and the
[system design](../../../DESIGN.md).

Dependencies used by this boundary are `RupaCoreTypes`, `RupaGeometry`,
`RupaProjectModel`, and Swift-CAD. Users include `RupaProject`, `RupaKit`, and
existing application/domain adapters through the public Core contracts.

Parent: [RupaKit package design](../../DESIGN.md). Children: none for T09.

## Responsibilities and Boundaries

`RupaCore` owns:

- `DesignDocument` Product metadata and retained representation references;
- retained Authored Mesh assets and their provenance;
- source-authority target validation using only `sourceID` and expected content
  identity;
- applying one complete Mesh plan through the injected Geometry executor;
- replacing only the matching asset after full success and preserving all
  Product/CAD/selection/provenance values;
- semantic document validation and Core command results.

It does not own Mesh algorithms, plan execution internals, project package I/O,
project revision publication, view projection, or Agent/CLI/MCP transport.
`SceneNodeID` and `GeometryRepresentationID` remain navigation/reference values
outside the Mesh source target; they are not required inverse references and do
not establish Mesh source authority.

```mermaid
flowchart LR
    Command["Source-authority Mesh plan command"] --> Validate["Core document + sourceID/content identity validation"]
    Validate --> Execute["Injected RupaGeometry plan executor"]
    Execute --> Replace["Replace matching Authored Mesh asset"]
    Replace --> Document["Validate staged DesignDocument"]
    Document --> Result["Immutable Core result + Mesh receipt"]
```

### Current baseline and T09 delta

The current Core path in
[AuthoredMeshEditCommand.swift](AuthoredMeshEditCommand.swift),
[AuthoredMeshEditTarget.swift](AuthoredMeshEditTarget.swift), and
[DefaultGeometrySourceCommandApplier.swift](DefaultGeometrySourceCommandApplier.swift)
accepts one operation and carries scene/representation IDs in its target. T09-B
replaces that public operation/target shape with one source-authority target and
one complete plan. The existing Core validation and transaction/history boundary
remain the integration point.

## Related Designs

| Design | Relationship | Contract Used | Summary | Cautions |
|---|---|---|---|---|
| [package design](../../DESIGN.md) | parent package | Package authority direction | Places Core between Geometry and Project. | Do not publish from Core directly. |
| [system design](../../../DESIGN.md) | system parent | Source identity, shared references, one-plan flow | Defines the cross-layer behavior. | Local document validation remains Core-owned. |
| [RupaGeometry design](../RupaGeometry/DESIGN.md) | depends on | Plan/executor/receipt and buffer contract | Supplies immutable result and copy telemetry. | Core must not reimplement Geometry algorithms. |
| [CAD/Mesh responsibility](../../../Rupa/CAD_MESH_RESPONSIBILITY_CONTRACT.md) | depends on | Authored Mesh authority, CAD coexistence, provenance | Defines representation meaning and CAD/Mesh independence. | Do not alter CAD or selection when editing Mesh. |
| [State and project contract](../../../Rupa/STATE_AND_PROJECT_CONTRACT.md) | coordinates with | Source history and transaction staging | Project owns publication and revision. | Core results are staged values until Project commits. |
| [RupaCore tests](../../Tests/RupaCoreTests) | verification owner | Source-authority behavioral tests | Owns current/stale/shared-reference proof. | Type/shape tests alone are insufficient. |

## Architecture

```mermaid
flowchart TD
    Target["AuthoredMeshSourceTarget\nsourceID + expected content identity"] --> Lookup["Retained asset lookup"]
    Lookup --> AssetCheck["Authored Mesh domain + asset key/sourceID"]
    AssetCheck --> Plan["AuthoredMeshEditPlan"]
    Plan --> Executor["RupaGeometry executor"]
    Executor --> Candidate["Candidate MeshSource + receipt"]
    Candidate --> Asset["Asset replacement preserving provenance"]
    Asset --> Validate["Full DesignDocument validation"]
    Validate --> Application["Staged Core application"]
```

An Authored Mesh asset may be referenced by multiple Product Objects or
representations. Source editing operates on that shared asset authority, so all
retained references observe the same replacement. Core never silently makes a
unique copy to satisfy a single scene selection.

## Contracts and Invariants

1. The Mesh edit target contains only `GeometrySourceID` and expected
   `ContentIdentity`. Scene-node and representation IDs are not part of source
   authority.
2. Core validates the Authored Mesh identity domain, the retained asset
   dictionary key, the asset source ID, and the expected content identity before
   invoking Geometry. A CAD-derived snapshot, external observation, or arbitrary
   Mesh payload cannot be promoted by identity imitation.
3. The target may name a retained-but-unselected asset; Core does not require an
   inverse Object or representation reference to apply the edit.
4. The Core command contains one complete plan. Core validates the returned
   geometry result and replaces the asset under the same source ID only after
   every plan step and full `DesignDocument` validation succeed.
5. Shared source references remain shared. Core does not clone the source or
   synchronize CAD, purpose selection, or representation metadata as a side
   effect.
6. CAD bytes, Product metadata, representation IDs, modeling/presentation
   selection, and Authored Mesh provenance are byte-for-byte/semantically
   invariant for a Mesh-only edit, except for the edited asset payload and its
   content identity.
7. A no-op plan preserves the asset content identity and produces a no-op result.
8. Plan receipt and copy telemetry survive the Core result boundary for Project
   staging and verification.
9. Core does not make a derived evaluation snapshot an Authored Mesh source;
   explicit Make Editable remains a separate command.

## Runtime Flows

```mermaid
sequenceDiagram
    participant P as Project staging
    participant A as Core applier
    participant E as Mesh executor
    participant D as DesignDocument

    P->>A: source-authority plan command
    A->>D: validate document and locate sourceID
    A->>A: compare expected content identity
    A->>E: execute plan against retained MeshSource
    E-->>A: candidate result + receipt
    A->>D: replace asset and validate complete staged document
    D-->>P: staged document + Core result
```

If execution or validation fails, the original document value remains unchanged.
The project layer decides whether and when the staged value is published.

## State, Ownership, and Lifecycle

- `DesignDocument` owns the retained asset dictionary and Product references.
- `RupaGeometry` owns the temporary mutable buffer during plan execution.
- `AuthoredMeshAsset` owns published Mesh source identity, payload, and
  provenance.
- Core application results are immutable staged values and do not publish by
  themselves.
- Undo/redo and transaction revision are recorded by `EditorSession`/
  `ProjectController` around the Core application, not inside the Geometry
  executor.

## Failure, Concurrency, and Constraints

Core rejects source-domain mismatch, an asset dictionary key/source-ID mismatch,
missing asset, stale content identity, invalid plan receipt, invalid Geometry
result, executor failure, and post-replacement document validation failure with
typed errors. It never returns the original asset as a success fallback after a
failed edit and it does not fail merely because no inverse Object/reference is
present.

The Core value path is immutable during asynchronous project staging. Any
mutable session access remains inside the existing project/session isolation
boundary. No `await`, package I/O, or external callback occurs during a Geometry
buffer borrow.

## Verification and Change Impact

T09-B owns the following behavioral proof:

| Invariant | Required evidence |
|---|---|
| Authority | Current, stale, missing, domain/key/source-ID, retained-but-unselected, and no-inverse-reference source cases. |
| Plan integration | One complete plan, receipt propagation, Geometry-result validation, no-op identity stability, and mid-plan rollback. |
| Shared source | One edited asset is visible through every retained representation reference; no implicit clone. |
| Independence | CAD/Product/selection/provenance bytes remain unchanged after Mesh edit. |
| History | One command-history entry plus undo/redo behavior. |
| Error handling | Typed failures do not publish a partial document. |

Changes to target identity, asset replacement, provenance, or Core command
decoding require rechecking `RupaProject` staging and the system source-authority
invariants.
