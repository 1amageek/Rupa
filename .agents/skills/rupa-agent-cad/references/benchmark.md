# Benchmark Evidence

## Choose the evidence mode

- **Recorded-evidence audit:** When asked whether the 100-case validation exists or what it proves, inspect the catalog, committed fixture, integration tests, design, and commits. Do not execute tests.
- **Current-snapshot revalidation:** Only when explicitly asked to run, rerun, benchmark, or revalidate, execute focused gates with a timeout and report exact dependency provenance.

Never turn a committed fixture into a claim that the current dirty workspace is green.

## Recorded T12 evidence

The current contract records exactly 100 unique ordered IDs, ten fixed
categories, 100 realized cases, zero unsupported cases, 100 correct capability
decisions, and source/B-Rep, rollback, cancellation, telemetry, and cleanup
evidence.

Historical commits `32d564f5` and `8e90c065` record 95 realized cases and five
`expectedUnsupported` spheres. They are provenance only, not evidence for the
current 100-realized contract.

## Evidence hierarchy

| Evidence | Proof boundary |
|---|---|
| Catalog validation | IDs, ordering, uniqueness, counts, and digest. |
| Per-case/category tests | Geometry, failure, telemetry, and cleanup contracts. |
| Serial integration | All cases traverse the production controller and oracle. |
| Integrated execution | Policy, drain, baseline, and canonical report compose. |
| JSON/CLI tests | External wire schema, bounds, exit behavior, and process boundary. |
| Live Rupa check | Current application session; separate from isolated T12 documents. |

Spec-derived scenarios and mock outputs may improve planning coverage, but they
do not replace exact source/B-Rep or live Rupa evidence.

## Full current-snapshot claim

Require: 100 results, 100 realized, zero unsupported, 100/100 correct capability
decisions, no drift, 100 started and completed, zero active cases and
registrations, canonical report equality, and recorded RupaKit/swift-CAD
commits plus dirty-state provenance.

Any execution failure invalidates a complete current-snapshot claim even when cleanup succeeds. Never update the fixture or baseline without an explicit reviewed baseline-change request.

## Source authorities

- `/Users/1amageek/Desktop/3D/RupaKit/Tests/RupaAgentCADBenchmarkTests/CADBenchmarkCatalogTests.swift`
- `/Users/1amageek/Desktop/3D/RupaKit/Tests/RupaAgentCADBenchmarkTests/CADBenchmarkSerialIntegrationTests.swift`
- `/Users/1amageek/Desktop/3D/RupaKit/Tests/RupaAgentCADBenchmarkTests/CADBenchmarkIntegratedExecutionTests.swift`
- `/Users/1amageek/Desktop/3D/RupaKit/Tests/RupaAgentCADBenchmarkTests/Fixtures/t12-reference-execution-v1.json`
- `/Users/1amageek/Desktop/3D/RupaKit/Sources/RupaAgentCADBenchmark/DESIGN.md`
