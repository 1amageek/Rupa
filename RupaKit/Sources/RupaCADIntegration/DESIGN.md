# RupaCADIntegration

## Purpose and Scope

`RupaCADIntegration` adapts one immutable Rupa CAD source reference to a
Swift-CAD exact evaluation and a bounded derived `MeshSource`. It is a child of
the [RupaKit package design](../../DESIGN.md) and has no child designs.

The exchange adapter in this module also converts a file-owned STEP, STL, or
OBJ input into a staged Core value. It retains exact STEP source as a
Swift-CAD `CADDocument`; STL and OBJ become validated Authored Mesh sources.

`CADDocumentEvaluationCache` is scoped by `(documentID, configuration)`, where
the configuration is the fidelity the meshes were tessellated at. The resource
ceiling is deliberately outside that scope: it is per-request admission, so a
ceiling that shrinks with the remaining allowance cannot move the scope on
every edit and evict the incremental evaluation the kernel reuses.

## Responsibilities and Boundaries

This module owns the mapping from Rupa's document CAD configuration to
Swift-CAD, exact source fingerprint validation, exact-evaluation reuse, derived
Mesh artifact caching, conversion to `MeshSource`, and per-request admission of
the produced meshes against the requesting allowance. The shared Mesh
materializer is the single owner of Swift-CAD `Mesh` to universal topology and
attribute conversion for both evaluated CAD and exchange imports. The exchange
adapter owns URL-byte admission, format dispatch, unit resolution, content
provenance, and immutable import results. It does not select fidelity, edit CAD
source, publish a project, render a viewport, handle Agent requests, or own
application file-panel lifetime.

The package-visible output-ID helper is the single owner of the existing
direct-`BodyID` and feature-to-unique-body interpretation; consumers use that
contract instead of reconstructing Swift-CAD ID semantics.

## Related Designs

| Design | Relationship | Contract Used | Summary | Cautions |
|---|---|---|---|---|
| [RupaKit package](../../DESIGN.md) | parent | module graph and authority direction | Places this adapter below product composition and provider-neutral evaluation. | This module is not project authority. |
| [RupaEvaluation](../RupaEvaluation/DESIGN.md) | depends on | bounded provider request/result | Declares the provider contract this adapter implements, with exact references and remaining aggregate allowance. | Return exactly the requested results or fail; the contract owner never imports this adapter. |
| [RupaKit integration](../RupaKit/DESIGN.md) | used by | document CAD configuration and evaluation cache | Builds the provider from the document's modeling settings and owns the cache it seeds a staged evaluation into. | The seed must be recorded under the same configuration a request looks up, or it is never reused. |
| [Swift-CAD](../../../swift-CAD/DESIGN.md) | depends on | exact evaluation and bounded tessellation | Supplies exact B-Rep and generic Mesh limits. | Swift-CAD never receives Rupa UI policy. |
| [RupaCore](../RupaCore/DESIGN.md) | used by | staged imported-Mesh command | Receives validated MeshSource values and owns Product/source identity allocation. | The adapter never mutates a DesignDocument or publishes a project. |

## Architecture

```mermaid
flowchart LR
    Config["Document CAD configuration\ntolerance + tessellation fidelity"] --> Provider["CADGeometrySourceProvider"]
    Source["Immutable CAD source + fingerprint"] --> Provider
    Allowance["Remaining evaluation allowance\nper request"] --> Provider
    Provider --> Exact["Exact reusable evaluation state"]
    Provider --> MeshCache["Mesh artifact cache\nsource + fidelity"]
    Exact --> SwiftCAD["Swift-CAD"]
    MeshCache --> SwiftCAD
    SwiftCAD --> MeshSource["Bounded immutable MeshSource"]
```

```mermaid
flowchart LR
    File["App-owned URL / security scope"] --> Adapter["Exchange import adapter"]
    Adapter -->|STEP + embedded units| Exact["Exact CADDocument source"]
    Adapter -->|STL/OBJ + explicit or embedded unit| Mesh["Validated MeshSource + content fingerprint"]
    Mesh --> Core["RupaCore import command"]
    Core --> Tx["ProjectSourceTransaction"]
```

## Contracts and Invariants

1. `CADGeometryEvaluationConfiguration` contains modeling tolerance and
   tessellation fidelity, and nothing else. It carries no resource ceiling,
   because ceilings are per-request admission and would otherwise move the
   cache scope; and no artifact purpose, because both representation purposes
   ask for the same fidelity of the same document and partitioning the cache
   between them would cost a full kernel evaluation on every alternation the
   publication path makes. It contains no viewport, camera, Agent,
   publication, or persistence state.
2. RupaKit composition supplies one configuration per document. This module
   validates and applies it without changing fidelity, and derives the kernel
   ceiling for a request as the module ceiling lowered to that request's
   remaining allowance.
3. Exact evaluation reuse is keyed by source identity/fingerprint, schema,
   evaluator identity, revisions, units, and modeling tolerance. It is not
   invalidated only because presentation tessellation fidelity differs.
4. Mesh artifact reuse is separate and requires the exact source fingerprint
   and the complete tessellation fidelity configuration. A reused artifact is
   charged against the requesting allowance like a freshly produced one,
   because a reused body may bypass a new kernel tessellation invocation; an
   artifact the current allowance does not admit is a typed refusal, not a
   cache miss.
5. The provider enforces the lower of the module tessellation ceiling and the
   remaining RupaEvaluation allowance before derived Mesh allocation, then
   returns exactly one validated result for every requested reference. Its
   admission accounts for final universal `MeshSource` storage (IDs, topology,
   corners, and converted attributes), not only kernel position/index arrays.
   For a request containing multiple CAD sources, each fresh source evaluation
   receives a newly lowered kernel limit derived from the already lowered
   module/request ceiling after every earlier kernel charge. The byte dimension
   is additionally capped by the universal allowance remaining after earlier
   `MeshSource` charges, because kernel and universal byte footprints differ.
   An exact cache hit skips kernel allocation but is still charged by universal
   admission. A source that cannot fit that remainder is refused by the
   evaluator before it allocates its mesh, while the provider's final aggregate
   guard remains authoritative for returned output.
   Edge-key preflight scratch is bounded by the byte-derived remaining edge
   capacity and is never reserved from the full kernel index count.
   The materialized source is measured again and must match the prediction
   before it can be cached. A kernel resource refusal is reported as resource
   exhaustion, an invalid ceiling as invalid configuration, and a cancellation
   is rethrown unchanged.
6. Cache publication is atomic for one provider evaluation. Failure,
   cancellation, stale source identity, or limit exhaustion publishes neither
   a partial result nor a reusable Mesh artifact.
7. Exchange import is bounded and typed. `CADGeometryExchange` accepts only
   STEP, STL, and OBJ, maps the App-owned URL through `MappedFileByteSource`,
   rejects a source larger than the configured exchange byte ceiling before a
   parser runs, and rethrows `CancellationError` unchanged. STEP imports
   preserve the reader's accepted exact entity subset and embedded units;
   unsupported entities remain `ImportError` failures. STL/OBJ imports require
   a format unit marker or an explicit caller-supplied unit before coordinates
   are accepted, with an embedded marker authoritative over the fallback.
   Source provenance records the normalized format domain, resolved length
   unit, and content fingerprint; paths, temporary files, and security-scoped
   URL state do not enter Core values. A unitless input imported with two
   different explicit fallbacks therefore cannot alias the same source
   identity.
8. Mesh exchange outputs are admitted with the same `CADTessellationAdmission`
   and `EvaluationAllowance` contract as evaluated CAD. Admission accounts for
   the final universal `MeshSource` footprint before materialization and the
   materialized source is measured again before it is returned. Unsupported
   materials and mixed exact/mesh parser results are typed refusals; no partial
   source array is returned.
9. The adapter returns immutable values only. Core stages them through the
   existing geometry-source command and Project owns atomic publication,
   cancellation, revision checks, undo/redo, and package persistence.

## Runtime Flows

```mermaid
sequenceDiagram
    participant E as RupaEvaluation
    participant P as CAD provider
    participant C as CAD evaluation cache
    participant K as Swift-CAD
    E->>P: references + revision + remaining allowance
    P->>C: lookup exact state and matching Mesh artifacts
    C-->>P: compatible exact candidate + admitted artifacts
    P->>K: exact evaluation reuse + explicit fidelity/limits
    K-->>P: complete exact B-Rep and bounded Mesh or typed failure
    P->>P: validate fingerprint, identities, Mesh, and actual usage
    P->>C: atomically publish complete cache entry
    P-->>E: exact requested immutable results
```

## State, Ownership, and Lifecycle

`CADDocumentEvaluationCache` owns immutable exact candidates and derived Mesh
artifacts behind its existing `Mutex`; it owns no mutable CAD document or
project state. Exact and Mesh entries are retained only for cache reuse and are
replaced atomically by newer compatible revisions. Provider requests and
conversion scratch are invocation-local.

## Failure, Concurrency, and Constraints

Evaluation is synchronous and `Sendable`; its caller chooses the task/executor.
No lock is held across external callback, I/O, or lengthy Swift-CAD work.
Invalid configuration, source mismatch, stale revision, missing body, malformed
Mesh, checked overflow, budget exhaustion, and cancellation remain typed. No
failure returns an empty or silently coarsened successful result.

## Verification and Change Impact

Tests must prove one evaluation serves both representation purposes at one
revision, exact B-Rep reuse survives a fidelity change, Mesh reuse requires its
complete artifact configuration, the remaining allowance reaches the kernel as
the lowered ceiling and refuses an exhausted request before the kernel is
entered, a cached artifact the current allowance no longer admits is refused
without a second evaluation, exhaustion and cancellation stay typed and
distinct from an unrelated failure, and failure or cancellation publishes no
partial cache entry. Changes require rechecking RupaEvaluation, RupaKit
composition, RupaProject staging, and Swift-CAD tessellation contracts.
