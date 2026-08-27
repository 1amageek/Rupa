# Rupa System Design

## Purpose and Scope

This is the system design master for the Rupa system. It indexes two separate
scopes: T10 Agent-to-project geometry integration and T11 professional bicycle
reference design. T10 connects the already implemented Agent CAD route and T09
Authored Mesh use cases without adding a second project authority or a
modeling-specific transport. T11 defines a bounded L2 engineering-reference
design and evidence contract; it does not extend the T10 runtime.

This document has no parent. Its direct children are the
[RupaKit package design](RupaKit/DESIGN.md), which indexes the changed module
designs, and the [professional bicycle reference design](Artifacts/professional-bicycle/DESIGN.md),
which defines the T11 engineering-reference acceptance boundary without adding
production code. The T09 Geometry/Core/Project/Mesh contracts remain the
verified lower foundation. T10 changes only their application and Agent
composition boundary; T11 consumes that boundary as an observed capability and
design-evidence dependency.

## Responsibilities and Boundaries

The system owns the cross-module rule that one registered `ProjectWorkspace`
serves CAD automation, Make Editable, Authored Mesh reads and edits, history,
presentation evaluation, and application-owned persistence.

It does not add an MCP server, CLI command, bicycle-specific command, new Mesh
kernel operation, renderer, or Agent file-lifecycle authority. T10's bicycle
workflow is a capability fixture composed from existing CAD automation
commands. The T11 child is a separate evidence/design branch and does not
change this runtime boundary.

## Related Designs

| Design | Relationship | Contract Used | Summary | Cautions |
|---|---|---|---|---|
| [RupaKit package](RupaKit/DESIGN.md) | child | T10 dependency and verification composition | Indexes Project, RupaKit, AgentProtocol, and AgentRuntime ownership. | Details remain in the owning module. |
| [CAD/Mesh responsibility](Rupa/CAD_MESH_RESPONSIBILITY_CONTRACT.md) | depends on | CAD modeling and Authored Mesh presentation authority | Defines retained representation meaning. | A derived evaluation snapshot is never persisted source. |
| [State/project contract](Rupa/STATE_AND_PROJECT_CONTRACT.md) | depends on | exact coordinates, staging, history, rollback, save ownership | Defines the sole project publication lifecycle. | Agent mutations never bypass `ProjectController`. |
| [Current task progress](RupaKit/PROGRESS.md) | coordinates with | work order and evidence ownership | Tracks the cumulative T10/T11 design, implementation, and integration proof. | A design checkbox is not behavior evidence. |
| [Professional bicycle reference](Artifacts/professional-bicycle/DESIGN.md) | child | T11 L2 fidelity, provenance, CAD authority, and rejection contract | Defines the bounded engineering-reference outcome for a later Agent-generated bicycle assembly. | It is a design/acceptance contract; it does not claim manufacturing, safety, certification, or production implementation. |

## Architecture

```mermaid
flowchart LR
    subgraph T10["T10 runtime integration"]
        Agent["Typed Agent request"] --> Runtime["RupaAgentRuntime"]
        Runtime --> Workspace["Shared ProjectWorkspace"]
        Workspace --> Project["ProjectController authority"]
        Project --> CAD["CAD modeling source"]
        Project --> Mesh["Authored Mesh source"]
        Project --> Eval["Presentation evaluation"]
        Eval --> Scene["UniversalViewportScene"]
        Scene --> Render["Existing Mesh renderer triangles"]
        App["Application file lifecycle"] --> Project
    end
    subgraph T11["T11 evidence/design branch"]
        Sources["Primary sources + observed capability"] --> Reference["L2 reference design"]
        Reference --> Acceptance["Validator and acceptance specifications"]
        Acceptance --> ArtifactEvidence["Persisted/rendered evidence plan"]
    end
    Runtime -. "observed by T11-R" .-> Sources
```

## Contracts and Invariants

1. Agent CAD operations continue to use the existing Automation request route;
   T10 introduces no bicycle-specific command.
2. Make Editable explicitly evaluates the selected CAD modeling representation,
   commits a new independent Authored Mesh representation, retains CAD and its
   modeling selection, and may switch only presentation selection. This is the
   general representation transition; it does not require a bicycle-specific
   body count or an all-body conversion.
3. Catalog, page, neighborhood, edit preview, and edit commit reuse the T09
   bounded use cases. AgentRuntime supplies the exact current full
   `ProjectViewSnapshot`; transport values do not become authority.
4. AgentProtocol reuses Codable RupaKit Mesh values through a one-way,
   cycle-free dependency. Results containing an in-process view are projected
   to AgentProtocol-owned DTOs rather than serializing the view.
5. Stale coordinates, cancellation, invalid limits/plans, and prepublication
   failures are typed and publish nothing. A postpublication projection failure
   returns the exact committed coordinate and must-not-retry disposition.
6. Agent requests do not save or load `.rupa` files. Application code retains
   that authority through `ProjectWorkspace`/`ProjectController`; the existing
   Agent save request remains unsupported.
7. Authored Mesh presentation evaluation shares immutable source buffers. A
   necessary Mesh edit copy is attributed at the T09 execution boundary.

T10's bicycle workflow is a capability fixture for the Agent route, authority
transition, application-owned save/load, and renderer traversal. Its
every-generated-body Make Editable loop is fixture-local. It proves neither
L2 dimensional coherence nor semantic bicycle parts, interfaces, manufacturing
readiness, structural safety, or certification. Those claims belong to the
separate T11 evidence/design branch and require its own acceptance contract.

## Runtime Flows

```mermaid
sequenceDiagram
    participant A as Agent request
    participant R as AgentRuntime
    participant W as ProjectWorkspace
    participant P as ProjectController
    participant V as Presentation renderer
    A->>R: existing CAD Automation batch
    R->>W: executeAutomation(exact view)
    W->>P: atomic CAD source transaction
    Note over A,P: T10 fixture may repeat Make Editable per fixture body; this is not a system-wide requirement
    A->>R: catalog/page/neighborhood/edit preview/commit
    R->>W: existing bounded T09 Mesh use cases
    W->>P: at most one Mesh source transaction
    Note over A,P: Agent has no save authority
    W->>P: application-owned save then load
    P->>V: presentation evaluation -> scene -> real triangles
    V-->>V: deterministic acceptance PNG
```

## State, Ownership, and Lifecycle

`ProjectController` owns Product, CAD, Authored Mesh, package, evaluation,
history, and publication sequence. `ProjectWorkspace` owns the observable exact
view. AgentProtocol owns only Codable messages; AgentRuntime owns only request
routing and registration leases. The acceptance PNG is generated test evidence
from loaded presentation triangles and is not source or package authority.

## Failure, Concurrency, and Constraints

Project actor isolation and registration operation leases remain the ordering
boundaries. Heavy bounded reads and geometry work use immutable snapshots
outside the actor and revalidate before return/publication. No retry is allowed
after a source mutation has published. Existing read/plan hard ceilings remain
the maximum accepted through Agent decoding.

## Verification and Change Impact

| Invariant | Behavioral evidence |
|---|---|
| Wire contract | Agent request/response codec and fixture tests for all typed Mesh and Make Editable routes, malformed limits/plans, and no fallback decoder. |
| Make Editable authority | Project/RupaKit tests for exact snapshot, CAD/modeling retention, presentation switch, provenance, zero-copy handoff, stale/cancel rollback, and one history entry. |
| Agent routing | Runtime tests proving each request reaches the registered workspace use case and preserves typed stale/cancel/no-retry failures. |
| T10 capability fixture | Agent CAD route, representation transition, application-owned save/load, renderer triangle traversal, and deterministic presentation output are exercised through the existing path. The fixture is not evidence of T11 L2 dimensional coherence, semantic bicycle parts, interfaces, manufacturing readiness, structural safety, or certification. |
| Portability | Focused Native runtime tests and compile/link evidence only for portable targets supported by their dependency graph; unavailable target entry failures are reported, not treated as success. |

Changes to Agent wire values, project authority, representation selection, file
lifecycle, or renderer input require rechecking the owning child design and this
system composition.
