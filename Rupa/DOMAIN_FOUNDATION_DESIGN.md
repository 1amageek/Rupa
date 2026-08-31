# Rupa Domain Foundation Design

## Status

This document turns `DOMAIN_EXTENSION_ARCHITECTURE.md` into an implementation
design for the first domain-extension milestones.

| Field | Value |
|---|---|
| Scope | M1-M3 implementation record plus CADAPI-D target contracts |
| Depends on | `DOMAIN_EXTENSION_ARCHITECTURE.md` |
| Transaction contract | `DOMAIN_TRANSACTION_CONTRACT.md` |
| Reference contract | `REFERENCE_ARTIFACT_CONTRACT.md` |
| Validation contract | `VALIDATION_CONTRACT.md` |
| Primary goal | Add domain extensibility and a generic semantic-program compiler without moving concrete domain knowledge into Swift-CAD, RupaCore, RupaAutomation, RupaUI, RupaCLIKit, or RupaAgentRuntime. |
| Non-goal | Implement architecture, turbomachinery, character, manufacturing, or simulation behavior directly in this phase. |

## Design Summary

The design separates neutral storage, generic semantic contracts, concrete
vocabularies, and prepared execution. Existing M1-M3 code implements the domain
registry path; the CADAPI-D program compiler and planned `RupaCADDomain` cutover
remain target design, not current implementation.

```mermaid
flowchart TD
    CoreStorage["RupaCore neutral storage DTOs"] --> ProductMetadata["ProductMetadata"]
    Foundation["RupaDomainFoundation\nregistries + generic program contracts"] --> CoreStorage
    Domain["Concrete domain module"] --> Foundation
    CADDomain["RupaCADDomain\nplanned CAD descriptors/lowerers"] --> Foundation
    CADDomain --> Automation
    UI["RupaUI"] --> Foundation
    CLI["RupaCLIKit"] --> Foundation
    Agent["RupaAgentRuntime"] --> Foundation
    Foundation --> Automation["RupaAutomation\nbinding-aware prepared execution"]
    Automation --> Core["RupaCore"]
```

| Part | Location | Why |
|---|---|---|
| Neutral stored data | `RupaCore` | `ProductMetadata` already lives in `RupaCore`, so stored DTOs cannot live in a higher module. |
| Registries and protocols | `RupaDomainFoundation` | UI, CLI, Agent, and concrete domains need a shared discovery contract without making `RupaCore` import domains. |
| Generic semantic program | `RupaDomainFoundation` | One domain-neutral operation/value/reference/DAG/compiler contract must serve both direct and program invocation without owning concrete CAD semantics. |
| Universal CAD vocabulary | Planned `RupaCADDomain` | Concrete CAD descriptors, schemas, validators, and lowerers remain outside the generic Foundation and execution substrate. |
| Prepared source execution | `RupaAutomation` | Binding-aware resolved operations execute on caller-owned staging; raw graph mutation remains an internal lowering substrate. |
| Concrete specialized behavior | Domain modules | Specialized semantics must remain above the universal CAD foundation. |

## Module Plan

### Existing Targets

| Target | Change |
|---|---|
| `RupaCore` | Add neutral semantic extension storage, projection manifest storage, validation hooks for structural consistency. |
| `RupaAutomation` | Own domain-neutral binding-aware prepared source execution. Keep raw `AutomationCommand` and feature-graph transactions internal to lowering rather than exposing them as Agent capabilities. |
| `RupaUI` | Consume capability/property descriptors from an injected registry in a later UI milestone. |
| `RupaAgentRuntime` | Merge registered domain capability descriptors into capability discovery without importing concrete domains. |
| `RupaCLIKit` | Add generic dispatch adapter for registered domain commands in a later CLI milestone. |

### Foundation and Planned Vocabulary Targets

| Target | Dependencies | Responsibility |
|---|---|---|
| `RupaDomainFoundation` | `RupaCore`, `RupaAutomation` | Namespace registry, capability registry, typed payload decoding, domain command lowering, validator and simulation adapter contracts. |
| Planned `RupaCADDomain` | `RupaDomainFoundation`, `RupaAutomation`, universal CAD public contracts | Concrete universal-CAD semantic operation descriptors, payload/result schemas, validators, and lowerers. This document does not claim that the target or cutover exists. |

`RupaDomainFoundation` must not be required to load or save a basic schema-v3 `.rupa`
document. Core documents remain valid without domain modules.

## RupaCore Storage Types

The following types belong in `RupaCore` because they are persisted by
`ProductMetadata`.

```mermaid
classDiagram
    class ProductMetadata {
      semanticExtensions
    }
    class SemanticExtensionEnvelope {
      id
      namespace
      schemaVersion
      payload
      projection
    }
    class ProjectionManifest {
      semanticEntitiesWithOwnership
      sourceReferences
      topologyReferences
      sceneReferences
      boundaryTags
      perEntityDependencyIdentity
    }
    class SemanticJSONValue
    ProductMetadata --> SemanticExtensionEnvelope
    SemanticExtensionEnvelope --> ProjectionManifest
    SemanticExtensionEnvelope --> SemanticJSONValue
```

| Type | Required fields | Responsibility |
|---|---|---|
| `SemanticNamespaceID` | raw string | Stable namespace such as reverse-DNS or product namespace. |
| `SemanticExtensionID` | UUID | Stable identity for one semantic model payload inside a document. |
| `SemanticSchemaVersion` | major, minor, patch | Stored compatibility metadata. |
| `SemanticJSONValue` | object, array, string, number, bool, null | Domain-neutral JSON payload preservation. |
| `SemanticExtensionEnvelope` | id, namespace, schemaVersion, payload, projection | One stored semantic payload plus its projection manifest. |
| `ProjectionManifest` | entities with ownership and dependency identity plus typed source, scene, topology, and boundary references | Mapping from semantic entities to universal CAD source and derived references. |
| `ProjectionSemanticEntity` | entity ID, ownership, semantic payload source paths, dependency identity when source-bound | Defines editable ownership and the exact semantic input set per entity rather than per envelope. |
| `ProjectionDependencyIdentity` | document ID, provenance generation, SHA-256 dependency fingerprint | Detects changes to one entity's transitive semantic, CAD, parameter, scene, component, plane, material, topology-binding, and referenced-entity dependencies without invalidating it for unrelated edits. |
| `ProjectionSourceReference` | feature ID, optional sketch/entity/body section | Links semantic entities to Swift-CAD source. |
| `ProjectionSceneReference` | scene node ID, object type ID | Links semantic entities to Rupa scene occurrences. |
| `ProjectionTopologyReference` | persistent topology name, role, owning feature | Links semantic entities to evaluated face/edge/vertex roles. |
| `ProjectionBoundaryTag` | semantic entity, tag kind, target reference | Links semantics to simulation or export boundary conditions. |
| `SemanticOwnershipPolicy` | domainOwned, universalOwned, classified | Defines who owns editable parameters. |

### Storage Shape

The storage shape lives in the Product source region at `source/product.json`.

```json
{
  "semanticExtensions": {
    "A4D0...": {
      "namespace": "architecture",
      "schemaVersion": { "major": 0, "minor": 1, "patch": 0 },
      "payload": { "walls": { "wall-1": { "height": 3.0 } } },
      "projection": {
        "semanticEntities": [
          {
            "id": "wall-1",
            "ownership": "domainOwned",
            "sourcePaths": [
              { "components": [
                { "kind": "key", "key": "walls" },
                { "kind": "key", "key": "wall-1" }
              ] }
            ],
            "dependencyIdentity": {
              "documentID": "...",
              "generation": 12,
              "fingerprint": {
                "algorithm": "sha256-projection-dependencies-v1",
                "value": "..."
              }
            }
          }
        ],
        "sourceReferences": [
          {
            "semanticEntityID": "wall-1",
            "featureID": "...",
            "ownership": "domainOwned"
          }
        ],
        "sceneReferences": [],
        "topologyReferences": [],
        "boundaryTags": []
      }
    }
  }
}
```

Large simulation results and heavy meshes must not be stored in `payload`. They
belong to derived artifact entries introduced by the simulation milestone.

## ProductMetadata Integration

`ProductMetadata` gains one optional/defaulted field:

| Field | Type | Default |
|---|---|---|
| `semanticExtensions` | `[SemanticExtensionID: SemanticExtensionEnvelope]` | `[:]` |

Validation remains structural in `RupaCore`.

| Validation | RupaCore behavior |
|---|---|
| Namespace is empty | Reject. |
| Schema version is invalid | Reject. |
| Envelope ID mismatch | Reject. |
| Projection references missing CAD source | Reject as invalid product metadata. |
| Projection references stale generation | Emit diagnostic through domain validation; do not reject load solely for staleness. |
| Unknown namespace | Preserve and structurally validate only. |
| Known namespace | Structural validation in RupaCore, semantic validation through registered domain validator. |

This keeps loading safe when a document includes a domain module not installed in
the current build.

## RupaDomainFoundation Contracts

The foundation target owns registries and generic semantic operation/program
contracts. It does not own stored document truth, concrete CAD operation
definitions, persistent identity allocation, source staging, or publication.

```mermaid
classDiagram
    class DomainRegistry {
      namespaces
      capabilities
      validators
      simulationAdapters
    }
    class DomainNamespaceRegistration
    class DomainCapabilityProvider
    class DomainCommandLowering
    class SemanticOperationDescriptor
    class SemanticProgram
    class SemanticProgramCompiler
    class DomainValidator
    class SimulationAdapter
    DomainRegistry --> DomainNamespaceRegistration
    DomainRegistry --> DomainCapabilityProvider
    DomainRegistry --> SemanticOperationDescriptor
    SemanticProgramCompiler --> DomainRegistry
    SemanticProgramCompiler --> SemanticProgram
    DomainRegistry --> DomainValidator
    DomainRegistry --> SimulationAdapter
```

| Protocol or type | Responsibility |
|---|---|
| `DomainRegistry` | Immutable registry of namespace, capability, validator, and simulation registrations. |
| `DomainNamespaceRegistration` | Namespace ID, supported schema versions, payload decoder, payload upgrader if needed. |
| `DomainPayloadDecoder` | Decode `SemanticJSONValue` into a typed domain payload. |
| `DomainCapabilityProvider` | Provide capability descriptors for UI, CLI, and Agent discovery. |
| `SemanticOperationDescriptor` | Stable operation ID/version, typed input and named-output schemas, effect, route eligibility, dry-run behavior, failure schema, and declared resource cost. |
| `SemanticValue` | Recursive typed literals, named parameters, existing source targets, typed local output references, and bounded pure expressions. |
| `SemanticProgram` | Order-independent bounded DAG whose unique local symbols invoke registered operations and connect typed named outputs to later inputs. |
| `SemanticProgramLimits` | Hard limits for bytes, decoded values/nesting, nodes, edges, parameters, local outputs, expressions, lowered commands, expanded source/evaluation work, and diagnostics. |
| `SemanticProgramCompiler` | Resolve one immutable registry and planning snapshot, validate the entire graph, deterministically topologically order it, verify every source route and aggregate effect, and emit one prepared plan before mutation. |
| `DomainCommandLowering` | Convert one validated semantic operation into binding-aware prepared source operations, an effect-specific immutable plan, or a typed failure. Direct and program forms use the same lowerer. |
| `DomainValidator` | Validate typed payload plus projection consistency and return structured diagnostics. |
| `DomainProjectionRepairProvider` | Provide repair/regeneration operations when projection state is stale. |
| `SimulationAdapter` | Prepare solver inputs and import analysis results as derived artifacts. |

The registry is value-based and injected. It must not use global mutable
singletons.

The CADAPI-D source-program subset accepts only operations that lower to the
common binding-aware source substrate. A descriptor classified as a document
mutation is not sufficient: each resolved operation must prove the source route
and the compiled aggregate must prove a source-mutation effect. Generic domain
transactions that cannot provide those guarantees remain single effect-specific
operations and are rejected from a source program.

Program nodes may use request-local symbols but never persistent `FeatureID`,
`SceneNodeID`, component, instance, or pattern IDs for newly produced values.
Those identities are allocated inside staged authority and projected back as
typed stable references only after successful publication. Programs contain no
loops, conditionals, recursion, callbacks, file I/O, or embedded scripting.
Registered native finite-pattern operations represent repeated structure
without wire expansion.

## Command Boundary

Domain commands are high-level operations, but their effects must still commit
through `ProjectWorkspace` and `ProjectController`. Foundation compiles intent;
it never owns staging or publication.

```mermaid
sequenceDiagram
    participant Caller as UI/CLI/Agent
    participant Workspace as ProjectWorkspace
    participant Registry as DomainRegistry
    participant Compiler as SemanticProgramCompiler
    participant Controller as ProjectController

    Caller->>Workspace: operation intent
    Workspace->>Registry: resolve capability from immutable snapshot
    Registry->>Compiler: decode, bind, preflight, and lower
    Compiler-->>Workspace: one prepared source plan
    Workspace->>Controller: one source transaction
    Controller-->>Caller: typed receipt and diagnostics
```

| Operation kind | Allowed commit path |
|---|---|
| Pure universal operation | Prepared through the registered semantic lowerer and executed by the binding-aware `RupaAutomation` source substrate. |
| Semantic payload plus CAD projection update | Atomic transaction defined by `DOMAIN_TRANSACTION_CONTRACT.md`: generic semantic-extension mutations plus universal commands staged, evaluated, and committed as one history entry. |
| Derived validation or simulation query | Non-mutating service result keyed by generation. |
| Solver-suggested geometry change | Explicit follow-up mutation command. |

No domain command may directly mutate `ProductMetadata`, bypass
`ProjectWorkspace`/`ProjectController`, bypass undo/redo, or expose a successful
state in which the semantic payload and CAD projection can be undone separately.
The complete source program produces at most one source transaction, exact
evaluation, undo entry, and publication. Prepublication failure or cancellation
leaves no state or persistent output mapping; a postpublication response failure
reports exact committed coordinates and must-not-retry semantics.

## Agent and CLI Design

Agent and CLI see domain functions as registered capabilities, not as hard-coded
enum cases for every domain. CAD source mutation has one semantic vocabulary and
two forms: `capability.invoke` invokes one operation directly, while
`program.execute` composes the same descriptors and lowerers as a bounded DAG.

| Surface | Design |
|---|---|
| Agent capabilities | Composed registry descriptors, including typed input and named-output parameters. Static raw Automation capabilities are legacy implementation inventory and are removed at CADAPI-D cutover. |
| Direct execution | `capability.invoke` carries one operation ID/version and typed payload. Eligible CAD mutation normalizes to a one-node program internally. |
| Program execution | `program.execute` carries shared coordinates, parameters, bounded nodes, and request-local typed references. It is not an array of independent requests. |
| CLI | CLI maps simple and program commands to the same access API and does not compile CAD operations, allocate persistent IDs, or mutate files directly. |
| Result | Typed receipt maps local named outputs to stable server references and exact committed coordinates, with diagnostics and retry classification. |

Domain discovery and execution use one descriptor contract. A parameter declares
its stable ID, nested payload path, value kind, payload unit, group, required and
nullable state, default, numeric bounds, and choices. `DomainCommandPayloadBuilder`
validates these contracts and constructs `SemanticJSONValue` payloads before the
request reaches domain lowering.

The current `domain.execute`, `command.apply`, `command.applyBatch`, raw
`AutomationCommand.appendFeatureGraph`, and caller-owned persistent-ID routes are
legacy implementation inventory. They remain reachable until the CADAPI-D
cutover is implemented and tested; this design does not claim their removal.

| Parameter kind | Payload contract | Current generic UI |
|---|---|---|
| Text, Boolean, integer, number | Unitless scalar | Implemented |
| Length | Number in meters; displayed in the document unit | Implemented |
| Angle | Number in degrees | Implemented |
| Choice | Registered stable string value | Implemented |
| Nullable scalar | Explicit `null` or a validated scalar | Implemented |
| Selection reference, collection, file, artifact | Typed contract not yet defined | Blocking future domain workflows |

## UI Design

The UI consumes descriptors and property schemas.

```mermaid
flowchart LR
    Registry["DomainRegistry"] --> Palette["Command palette/tool catalog"]
    Registry --> Inspector["Inspector property schema"]
    Registry --> Overlays["Viewport overlay descriptors"]
    Inspector --> Command["Command-backed property edit"]
    Command --> Store["CADDocumentStore"]
```

| UI feature | Data source |
|---|---|
| Tool availability | Capability registry and active profile policy. |
| Command inputs | `DomainCommandParameterDescriptor` rendered by `WorkspaceDomainCommandPanel`. |
| Command execution | Generation-safe `DomainCommandRequest` dispatched through `DomainCommandExecutor`. |
| Inspector fields | `SemanticObjectDescriptor` and object property schema. |
| Validation panel | Domain validator diagnostics. |
| Viewport overlays | Domain overlay descriptors rendered by generic viewport services. |
| Disabled state | Capability preflight result, not duplicated SwiftUI logic. |

## Ownership and Editing Rules

Every semantic entity and generated source mapping must have one owner. One
envelope may contain entities with different ownership policies.

| Source state | Edit behavior |
|---|---|
| `domainOwned` projection | Route compatible edits to the domain capability. |
| `universalOwned` CAD source | Use normal universal CAD commands. |
| `classified` metadata | Allow CAD edits; update or invalidate classification if references change. |
| Unknown namespace | Preserve payload; reject semantic edits; allow universal CAD edits only if they do not require unknown projection repair. |
| Stale projection | Allow read, validation, and repair; block unsafe semantic mutation. |

Direct subobject edits are allowed only when the resolver can prove the edit
maps back to a single editable semantic parameter. Otherwise the user or Agent
must explicitly convert that projection region to universal CAD ownership.

## Design Process Integration

Every domain capability must produce a design packet before implementation.

| DBN artifact | Domain requirement |
|---|---|
| DesignIntent | User-visible domain operation and ownership model. |
| DomainModel | Semantic payload schema, source projection, derived artifacts. |
| MappingSpec | UI, CLI, Agent, Automation, Core, generator, validator, simulation routes. |
| ConstraintBoundMapping | Ownership, units, tolerances, feature references, projection consistency. |
| FlowGraph | Ports from domain capability through command stack, evaluation, diagnostics, and display. |
| ValidatedArtifact | Tests proving storage, command, validation, and unknown namespace behavior. |

## Test Plan

| Test target | Required coverage |
|---|---|
| `RupaCoreTests` | ProductMetadata round-trip, unknown namespace preservation, structural validation, projection reference validation. |
| `RupaDomainFoundationTests` | Registry duplicate rejection, payload decoder routing, capability descriptor discovery, parameter schema validation, nested payload construction, validator dispatch, plus CADAPI-D direct/program descriptor equivalence, deterministic DAG ordering, typed local binding, missing/duplicate symbols, cycles, type mismatch, route/effect rejection, and every resource limit before mutation. |
| `RupaManufacturingTests` | Manufacturing namespace registration, injected process catalog discovery, unknown-process rejection, process-family result payloads, powder-analysis limitation reporting, face-process conflict rejection, non-mutating dispatch, dry-run behavior, unsupported payload rejection, missing-body diagnostics, build-volume pass/fail checks, required-material failure, assigned-material validation/export pass, mesh readiness, wall-thickness and clearance failures, STL/3MF/STEP preflight, and unfinished ledger gate coverage. |
| `RupaAutomationTests` | Binding-aware prepared source execution, controller-allocated output mapping, native-pattern non-expansion, and whole-program one transaction/evaluation/undo/publication with rollback on every prepublication failure. |
| `RupaAgentTests` | Both invocation forms use the same registered descriptor/lowerer, raw graph and caller-owned persistent IDs are absent or rejected after cutover, and postpublication response failure is must-not-retry. |
| `RupaCLITests` | Actual direct/program access dispatch, explicit save, reload, and no transport-to-file fallback. |

Tests must first prove that a document with no registered domains still loads,
saves, validates, and evaluates exactly as before.

## Milestone Breakdown

```mermaid
flowchart TD
    M1A["M1A RupaCore storage DTOs"] --> M1B["M1B ProductMetadata integration"]
    M1B --> M1C["M1C Structural validation tests"]
    M1C --> M2A["M2A RupaDomainFoundation target"]
    M2A --> M2B["M2B Registry and decoder contracts"]
    M2B --> M2C["M2C Capability and validator dispatch tests"]
    M2C --> M3A["M3A Projection ownership resolver"]
    M3A --> M3B["M3B Domain command lowering contract"]
    M3B --> M3C["M3C Agent/CLI execution implementation"]
```

| Milestone | Done state |
|---|---|
| M1A | Neutral DTOs compile in `RupaCore`; no domain target exists yet. |
| M1B | `ProductMetadata.semanticExtensions` round-trips through `source/product.json` in a schema-v3 `.rupa` package. |
| M1C | Unknown namespaces are preserved and structurally validated. |
| M2A | `RupaDomainFoundation` target exists and depends only on approved modules. |
| M2B | Registries reject duplicate namespaces/capabilities and route decoders deterministically. |
| M2C | Validators and capability descriptors are discoverable without concrete domain imports in runtime consumers. |
| M3A | Ownership resolver can classify domain-owned, universal-owned, classified, unknown, and stale projections per semantic entity. |
| M3B | Domain operations can lower to atomic staged transactions or immutable snapshot queries; query providers cannot access a mutable `EditorSession` or construct execution identity/generation/mutation flags. |
| M3C | Agent and CLI can discover and execute registered domain capabilities through injected registries. |

## Current Implementation Status

| Milestone | Status | Evidence | Remaining gate |
|---|---|---|---|
| M1A | Implemented | `RupaCore` semantic DTOs compile and use single-value Codable IDs for stored payload readability. | Broader schema migration policy. |
| M1B | Implemented | `ProductMetadata.semanticExtensions` saves as a UUID-keyed object and round-trips through `source/product.json` in a schema-v3 `.rupa` package. | Package-level artifact entries for large derived results. |
| M1C | Implemented | Structural tests cover missing legacy field, invalid UUID keys, key/envelope mismatch, missing source references, and non-finite JSON numbers. | More projection reference variants as domain pilots add them. |
| M2A | Implemented | `RupaDomainFoundation` target depends on `RupaCore` and `RupaAutomation`, not concrete domains; `ArchitectureBoundaryTests` enforce source-import boundaries and Package.swift production target dependency rules for Core, Automation, DomainFoundation, Agent, CLI, UI, and concrete domain modules. | Keep the expected production target graph updated as new modules are added. |
| M2B | Implemented | `DomainRegistry` routes payload decoders, validators, command lowerings, projection repair providers, and simulation adapters. | Registry composition from app/plugin roots. |
| M2C | Implemented | Agent, CLI, and RupaUI consume injected domain capability descriptors without importing concrete domain modules. Typed scalar/choice parameters are preserved through Agent discovery and rendered by a generic Workspace execution panel. | Selection-reference, collection, file, and artifact parameter contracts. |
| M3A | Implemented foundation | Ownership resolves per semantic entity. Source-bound entities carry exact transitive dependency identities; generation-only and unrelated document edits do not mark them stale. Missing identities, conflicting mapping targets, invalid topology owners, and broken references fail structural validation. | Add per-source edit preflight and explicit ownership-transfer capabilities. External linked-source freshness requires the future external dependency resolver. |
| M3B | Implemented foundation | Domain mutations stage universal commands and semantic mutations in an isolated session, canonicalize per-entity dependency identities after universal source changes, evaluate the final state, and publish one coherent editor state and undo entry. Immutable queries cannot access `EditorSession` or construct executor-owned result identity. | Add effect-specific artifact, export, and external-job executors plus measured staging budgets. |
| M3C | Implemented through the shared access route | Agent protocol exposes `domain.execute`; `AgentCommandController` dispatches it through the injected `DomainRegistry`; CLI callers send the same domain intent through one `ProjectAccessSession`; typed parameter descriptors are published through Agent capability discovery; RupaUI builds generation-safe nested payloads and executes registered scalar/choice commands from `WorkspaceDomainCommandPanel`; `DomainRegistry.merged` composes independent registries; `AgentHost` accepts injected registry and export service dependencies; the macOS app composes the initial Manufacturing registry once and injects it into both `MainView` and `AgentHost`, while also injecting a Manufacturing export preflight validator into `DocumentExportService`. Focused Foundation/Manufacturing/Agent/CLI/UI tests cover this current route only. | Keep semantic validation and lowering in Foundation, and verify the signed live project/session API preserves the App-owned authority, coordinate, rollback, and explicit-save contracts. |

## Open Decisions

| Decision | Current direction | Blocking milestone |
|---|---|---|
| Raw JSON storage representation | Use `SemanticJSONValue` for small semantic payloads. | M1A |
| Large artifact package entries | Add artifact manifest and package entries during simulation milestone, not M1. | M8 |
| Agent mutation request forms | CADAPI-D resolves the target to `capability.invoke` for one operation and `program.execute` for a bounded DAG of the same operations. Current `domain.execute` is legacy implementation inventory until cutover. | CADAPI-D |
| Domain-backed editor command shape | Resolved by `DOMAIN_TRANSACTION_CONTRACT.md`: use a neutral staged transaction with generic semantic-extension mutations and universal commands, committed as one history entry. | M3B |
| Profile gating | Profiles filter visible capabilities, but do not change command behavior. | Later profile milestone |
