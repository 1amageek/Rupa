# Agent Modeling Performance

## Objective

An Agent must be able to author a coherent model with work proportional to the
affected geometry, not the number of protocol round trips multiplied by the
size of the complete document.

```mermaid
flowchart LR
    Agent["Agent modeling plan"] --> Batch["Typed automation batch"]
    Batch --> Stage["Isolated source command group"]
    Stage --> Eval["One final incremental exact evaluation"]
    Eval --> History["One undo entry"]
    History --> Result["Compact receipts + optional final context query"]
```

## Current Contract

| Boundary | Required behavior |
|---|---|
| Protocol | Send related operations through `command.applyBatch` in one request. |
| Source staging | Apply source commands to an isolated session. Intermediate state is not published. |
| Evaluation | Defer ordinary evaluation requests and perform one final evaluation after all source commands succeed. |
| Validation | Reject the complete group when final evaluation does not reach the proposed generation or fails. |
| Undo | Record one before/after history entry for the complete group. |
| Result | Preserve command-specific IDs and reports for every command. Mutation receipts stay compact. A final explicit `describeDocument` command adds model bounds, precision, scale, grid, saved views, and diagnostics without another round trip. |
| Observability | Return command, evaluation, history, rich-result, feature reuse, body tessellation, scoped-read, and topology-mutation counts. A normal source batch targets `N / 1 / 1 / 0`; appending `describeDocument` targets `N+1 / 1 / 1 / 1`. |

`DocumentEvaluator` validates the geometry it has just generated without
re-evaluating the source. Full source re-evaluation remains part of explicit
freshness auditing for persisted or externally supplied caches and official
exchange export.

## Blender Comparison

Blender's performance comes from execution boundaries rather than Python
syntax alone:

| Blender mechanism | Rupa equivalent | Status |
|---|---|---|
| Direct data API for context-independent scripting | Typed Automation and Core commands | Partial; command vocabulary is broad, but some workflows still require discovery round trips. |
| BMesh editing followed by one explicit mesh update | `BRepEditBuffer` plus one final publish/evaluation boundary | Implemented for incremental exact topology replay. |
| Deferred dependency-graph recalculation | Deferred group evaluation | Implemented at source-command-group granularity. |
| Tagged dependency-graph updates of affected data | Dependency-closure invalidation and cached exact feature outputs | Implemented; unchanged feature results and meshes are reused. |
| Grouped undo | One command-history entry per source group | Implemented. |
| In-process scripts and operators | One socket request carrying a typed batch | Implemented. |

Primary references:

- [Blender BMesh API](https://docs.blender.org/api/current/bmesh.html)
- [Blender operator API](https://docs.blender.org/api/current/bpy.types.Operator.html)
- [Blender Python operator constraints](https://docs.blender.org/api/current/info_gotchas_operators.html)
- [Blender dependency graph](https://developer.blender.org/docs/features/core/depsgraph/)

## Remaining Performance Milestones

### P1: Referencable Modeling Programs - Complete

An Agent must reserve stable source IDs before execution and use them in later
commands in the same batch. Until this exists, workflows that create a feature
and then require its server-generated ID still need a round trip.

Acceptance:

- caller-reserved IDs are validated before staging;
- later commands can reference earlier reserved outputs;
- failure leaves no reserved identity published;
- the complete program still evaluates and records history once.

### P2: Incremental Feature Evaluation - Complete for the default evaluator

Cache feature inputs, outputs, and dependency identities. A source mutation
invalidates the changed feature and its downstream closure. Unaffected branches
must reuse exact evaluated outputs.

Acceptance:

- evaluation metrics report visited, reused, and invalidated feature counts;
- parameter changes only revisit dependent features;
- topology names remain stable across reused and rebuilt branches;
- full evaluation and incremental evaluation produce equivalent exact results.

### P3: Mutable Topology Edit Buffer - Complete for incremental replay

Provide a Core-owned edit representation for repeated vertex, edge, and face
operations. Validate and publish it once, analogous to BMesh's edit/update
boundary, without making mutable topology part of authoritative document source.

### P4: Interactive and Background Scheduling - Pending

Separate preview-quality cancellable evaluation from exact commit evaluation.
Interactive tools may coalesce superseded previews; committed Agent
transactions must remain deterministic and exact.

### P5: Stable Topology Identity Across Every Evaluator - In Progress

`PlanarExtrudeFeatureEvaluator` derives topology IDs deterministically from the
source feature ID. Revolve, sweep, loft, surface, Boolean, and direct-edit
evaluators still contain generated UUID paths and must migrate before stable
topology can be claimed for the complete operation vocabulary.

### P6: Independent-Branch Parallel Evaluation - Pending

The dependency graph identifies the exact invalidation closure, but the default
evaluator still rebuilds invalidated features serially. Independent branches
require deterministic parallel scheduling, isolated result buffers, and ordered
merge validation.

### P7: Compact Agent Program Transport - Pending

The decoded Agent execution path is benchmarked separately from request
serialization. Large explicit feature graphs still produce large JSON payloads.
The transport contract needs a compact, typed modeling-program representation
before socket or MCP end-to-end latency can be compared with an in-process
Blender script.

## Measured Baseline

Apple Silicon release measurements on 2026-07-11 use 100 independent exact box
bodies. Rupa uses 500 iterations and Blender uses 300 iterations after 50 and
30 warmups respectively. Values are median / p95:

| Boundary | Create 100 bodies | Edit one body |
|---|---:|---:|
| Rupa Kernel | 7.198 / 7.701 ms | 0.191 / 0.262 ms |
| Rupa Core | 7.599 / 8.132 ms | 0.196 / 0.276 ms |
| Rupa decoded Agent command | 7.585 / 8.124 ms | 0.208 / 0.277 ms |
| Blender mesh baseline | 4.250 / 4.656 ms | 0.139 / 0.165 ms |

The decoded Agent comparison passes all four `2.0x` gates:

| Gate | Ratio | Result |
|---|---:|---|
| Create median | 1.78x | Pass |
| Create p95 | 1.74x | Pass |
| Edit median | 1.49x | Pass |
| Edit p95 | 1.68x | Pass |

A second independent 300-iteration Rupa run also passes all four gates. With
1,000 bodies, decoded Agent edit latency remains 0.186 / 0.232 ms, confirming
that local extrusion edits are proportional to affected geometry rather than
document body count.

The 1,000-body scale check also remains within the gate:

| Workload | Rupa decoded Agent | Blender mesh baseline | Ratio |
|---|---:|---:|---:|
| Create 1,000 bodies | 77.467 / 84.822 ms | 65.402 / 68.248 ms | 1.18x / 1.24x |
| Edit one of 1,000 bodies | 0.186 / 0.232 ms | 1.635 / 1.964 ms | 0.11x / 0.12x |

Encoding the explicit 100-body Agent request remains 14.806 / 15.770 ms for a
573,155-byte payload. It is reported but excluded from the decoded execution
gate because the Blender baseline also excludes script generation and parsing.

The Blender workload edits raw mesh vertices. Rupa edits parametric source,
rebuilds exact BRep topology, tessellates the affected body, records undo, and
returns an Agent command receipt. These are useful end-user latency comparisons,
but not equivalent kernel workloads. The benchmark therefore reports Kernel,
Core, and Agent boundaries separately.

## Known Limits

The shared decoded execution workload is Blender-equivalent under the defined
latency gate. This is not a claim of parity for every CAD operation or for
socket/MCP end-to-end latency. Operation families beyond extrude still need
deterministic topology allocation, invalidated independent branches are serial,
preview evaluation is not cancellable or coalescing, and explicit feature-graph
JSON remains larger than a procedural modeling program.
