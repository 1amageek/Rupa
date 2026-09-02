# Semantic Capability Contract

T12 contains ten categories and exactly 100 benchmark cases. A case combines a
target specification, production route, oracle, failure behavior, telemetry,
and cleanup contract. It is not an independent public API or an operation
catalog.

| Category | Cases | Canonical outcome |
|---|---:|---|
| `LIN` | 12 | realized |
| `REC` | 12 | realized |
| `CIR` | 12 | realized |
| `ANG` | 16 | realized |
| `BOX` | 12 | realized |
| `CYL` | 8 | realized |
| `CON` | 8 | realized |
| `TRN` | 8 | realized |
| `CMP` | 7 | realized |
| `SPH` | 5 | realized |

The fixed denominator is 100. The current acceptance score is 100 realized,
zero unsupported, and 100 correct capability decisions.

## Selection rules

- Discover the live semantic-operation descriptors before every plan. Select by
  descriptor semantics and typed inputs/outputs; do not copy operation IDs from
  this benchmark reference.
- Operation-name agreement is not sufficient. Validate every required argument's
  semantic role, name, value, type, unit, and format before dispatch; do not fill
  an ambiguous optional argument from an assumed default.
- Preserve units, plane frames, source orientation, centers, axes, axis points, member order, output roles, and constraints explicitly.
- Reject non-finite coordinates, non-positive dimensions, and zero axes before publication.
- Use ordered role-bearing compound actions for multi-member results.
- Do not substitute Mesh appearance for analytic CAD evidence.
- Analytic sphere cases require analytic CAD surfaces and exact radius, center,
  topology, and volume observations.
- Transform and other source-consuming operations require a same-program local
  output or an exact same-session existing reference. Classify
  `sourceReferenceUnavailable` as a prepublication provenance failure.

## Outcome meanings

| Outcome | Meaning |
|---|---|
| `realized` | Production publication and exact source/B-Rep oracle passed. |
| `expectedUnsupported` | A requested live operation was genuinely unavailable and no mutation occurred; it is not a valid outcome for the current 100-case acceptance run. |
| `unexpectedUnsupported` | Capability handling or declaration was incorrect. |
| `invalidSubmission` | Input or geometric precondition failed. |
| `executionFailure` | Production route failed; preserve the typed error. |
| `timeout` or `cancellation` | Not realized; verify cleanup and publication state. |
| `oracleFailure` | Observed geometry did not satisfy the exact target. |

## Source authorities

- `/Users/1amageek/Desktop/3D/RupaKit/Sources/RupaAgentCADBenchmark/Candidate/CADBenchmarkCategory.swift`
- `/Users/1amageek/Desktop/3D/RupaKit/Sources/RupaAgentCADBenchmark/CADBenchmarkCatalog.swift`
- `/Users/1amageek/Desktop/3D/RupaKit/Sources/RupaAgentCADBenchmark/DefaultCADActivatedCaseExecutor.swift`
- `/Users/1amageek/Desktop/3D/RupaKit/Sources/RupaAgentRuntime/AgentCapabilityCatalog.swift`
