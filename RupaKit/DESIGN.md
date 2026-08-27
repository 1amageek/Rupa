# RupaKit Package Design

## Purpose and Scope

This document is the package-level design for the `RupaKit` Swift package. It
composes the verified T09 Mesh-editing foundation with the T10 Agent-to-project
geometry route while keeping one existing project authority.

Parent: [system design](../DESIGN.md). Direct children used by T10 are:

- [RupaGeometry](Sources/RupaGeometry/DESIGN.md)
- [RupaCore](Sources/RupaCore/DESIGN.md)
- [RupaProject](Sources/RupaProject/DESIGN.md)
- [RupaKit integration target](Sources/RupaKit/DESIGN.md)
- [RupaAgentProtocol](Sources/RupaAgentProtocol/DESIGN.md)
- [RupaAgentRuntime](Sources/RupaAgentRuntime/DESIGN.md)

Package dependencies are the local targets and external packages declared by
[`Package.swift`](Package.swift), notably `swift-CAD`, Swift Collections, and
Argument Parser. Package users are the system root, application targets, and
existing UI/Agent/CLI adapters through their declared target dependencies.

The package also contains existing targets such as `RupaEvaluation`,
`RupaProjectModel`, `RupaProjectPackage`, UI, rendering, and transport adapters.
Their current ownership remains indexed by [ARCHITECTURE.md](ARCHITECTURE.md).

The package design is the parent of the changed and reused module designs. It is not
a replacement for the system source-authority or state contracts linked below.

## Responsibilities and Boundaries

The package design owns:

- the dependency direction between provider-independent Mesh editing, source
  authority, project orchestration, and application integration;
- the rule that every T09/T10 layer uses the existing `ProjectController` authority;
- package-wide API and verification boundaries for T10.

It does not own Mesh topology algorithms, CAD semantics, source asset mutation,
archive encoding, socket I/O, MCP, CLI, or a bicycle-specific command. Those
are delegated to child designs or existing normative contracts.

```mermaid
flowchart LR
    CoreTypes[RupaCoreTypes] --> Geometry[RupaGeometry]
    CoreTypes --> Core[RupaCore]
    Geometry --> Core
    ProjectModel[RupaProjectModel] --> Core
    Core --> Project[RupaProject]
    Evaluation[RupaEvaluation] --> Project
    Package[RupaProjectPackage] --> Project
    Geometry --> Evaluation
    Project --> Kit[RupaKit target]
    Core --> Kit
    Geometry --> Kit
    ProjectModel --> Kit
    Kit --> UI["RupaUI"]
    Kit --> AgentProtocol[RupaAgentProtocol]
    AgentProtocol --> AgentRuntime[RupaAgentRuntime]
    Kit --> AgentRuntime
```

## Related Designs

| Design | Relationship | Contract Used | Summary | Cautions |
|---|---|---|---|---|
| [system design](../DESIGN.md) | parent | System authority and T10 cross-boundary invariants | Defines the complete Agent-to-presentation flow. | Child documents provide local details; do not duplicate them here. |
| [CAD/Mesh responsibility](../Rupa/CAD_MESH_RESPONSIBILITY_CONTRACT.md) | depends on | Representation roles, Authored Mesh authority, derived snapshots, zero-copy baseline | Defines the meaning of the source being edited. | A plan cannot turn a derived evaluation snapshot into source. |
| [State and project contract](../Rupa/STATE_AND_PROJECT_CONTRACT.md) | depends on | Project actor, revision, history, cancellation, and publication | Defines the lifecycle used by `RupaProject`. | Do not introduce a parallel session or publication sequence. |
| [ARCHITECTURE.md](ARCHITECTURE.md) | coordinates with | Existing package graph and application route | Records existing targets and shared workspace composition. | Task-specific contracts remain in this hierarchy. |
| [RupaGeometry design](Sources/RupaGeometry/DESIGN.md) | child | Plan/executor/buffer contract | Owns Mesh operation and performance semantics. | Package consumers use its public contracts only. |
| [RupaCore design](Sources/RupaCore/DESIGN.md) | child | Source identity and asset mutation contract | Owns Product/Authored Mesh source authority. | Scene references are navigation context, not authority. |
| [RupaProject design](Sources/RupaProject/DESIGN.md) | child | Staging/publication contract | Owns project transaction integration. | Geometry algorithms remain below this boundary. |
| [RupaKit integration design](Sources/RupaKit/DESIGN.md) | child | Transport-neutral read/edit and Make Editable use cases | Owns application-facing exact-snapshot adaptation. | T10 adds only AgentProtocol/Runtime adapters; CLI/MCP remain unchanged. |
| [RupaAgentProtocol design](Sources/RupaAgentProtocol/DESIGN.md) | child | Codable Agent Mesh and Make Editable messages | Reuses RupaKit value contracts without duplicating geometry meaning. | It must not import runtime or transport. |
| [RupaAgentRuntime design](Sources/RupaAgentRuntime/DESIGN.md) | child | Registered-workspace request routing | Binds wire values to the exact current full project view. | It never creates a session or saves a package. |

## Architecture

The package composes contracts from the bottom up:

```mermaid
flowchart TD
    Types["RupaCoreTypes\nIDs + identities"] --> G["RupaGeometry\nplan / executor / buffer"]
    Types --> C["RupaCore\nsource authority"]
    G --> C
    C --> P["RupaProject\ntransaction staging"]
    P --> K["RupaKit\nworkspace use cases"]
    P --> E["evaluation + package\nexisting boundaries"]
```

This direction avoids leaking project coordinates into the geometry kernel and
avoids making `RupaGeometry` depend on `RupaCore` or `RupaProject`.

## Contracts and Invariants

The package-level contract is limited to dependency direction and design
authority. Detailed Mesh operations, source targets, project staging, and read
records are owned by the four child designs:

| Package rule | Owner |
|---|---|
| `RupaCoreTypes` is the dependency floor. | Existing package graph. |
| `RupaGeometry` does not depend upward on Core, Project, UI, or transport. | [RupaGeometry design](Sources/RupaGeometry/DESIGN.md) |
| `RupaCore` is the source-authority boundary; `RupaProject` is the publication boundary. | [RupaCore design](Sources/RupaCore/DESIGN.md), [RupaProject design](Sources/RupaProject/DESIGN.md) |
| `RupaKit` is the application use-case boundary over existing Project authority. | [RupaKit integration design](Sources/RupaKit/DESIGN.md) |
| Existing CAD/Mesh and state contracts remain authoritative for their domains. | [CAD/Mesh responsibility](../Rupa/CAD_MESH_RESPONSIBILITY_CONTRACT.md), [state/project contract](../Rupa/STATE_AND_PROJECT_CONTRACT.md) |

The package design does not repeat those contracts and does not introduce a
second authority or source clone. T10 adds only the typed Agent adapter surface
over the existing RupaKit use cases.

## Runtime Flows

The package composes the child module flows in the order shown by the system
root. The package itself owns no request state and adds no alternate flow.

See the [system runtime flow](../DESIGN.md#runtime-flows), then the local flows
in [RupaGeometry](Sources/RupaGeometry/DESIGN.md#runtime-flows),
[RupaCore](Sources/RupaCore/DESIGN.md#runtime-flows),
[RupaProject](Sources/RupaProject/DESIGN.md#runtime-flows), and
[RupaKit](Sources/RupaKit/DESIGN.md#runtime-flows).

## State, Ownership, and Lifecycle

The package owns no shared mutable T10 state. State and lifetime are delegated
to the child owners: Mesh buffers to `RupaGeometry`, source assets to
`RupaCore`, project publication to `RupaProject`, and observable workspace view
to `RupaKit`.

## Failure, Concurrency, and Constraints

The package preserves the native target dependency graph and does not weaken
the isolation contracts owned by its children. Child failures remain typed and
are not converted at the package boundary. Concurrency, resource, and
zero-copy constraints are defined and verified by the owning module designs.

## Verification and Change Impact

The package-level proof is compositional and checks reachability of the child
contracts rather than duplicating their behavioral cases:

| Stage | Verification owner | Evidence |
|---|---|---|
| Geometry contract | `RupaGeometry` | T09-A tests for plan, topology, IDs, limits, rollback, and copy telemetry. |
| Source authority | `RupaCore` | T09-B tests for source identity, shared references, and invariance. |
| Project integration | `RupaProject` | T09-C and T09-IV tests for exact coordinates and atomic publication. |
| Application use case | `RupaKit` target | T09-C tests for bounded read/preview/commit. |
| Full package | Integration | T09-IV build/test and actual save/load path. |
| Agent wire and dispatch | `RupaAgentProtocol` / `RupaAgentRuntime` | T10-B codec, malformed-input, registered-workspace, stale/cancel, and no-retry tests. |
| Actual rendered workflow | T10 integration | Agent CAD bicycle assembly, Make Editable for every generated body, one representative Mesh edit, application save/load, all-Authored-Mesh presentation evaluation, renderer triangles, and deterministic PNG. |

Any public contract or dependency change requires rechecking the system root,
the affected child design, and the existing architecture/normative links.
