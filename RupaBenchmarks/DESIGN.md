# RupaBenchmarks

## Purpose and Scope

This package restores the verification assets removed in commit d10c7605,
without returning measurement-only targets to the production RupaKit package.
Its parent is the [system design](../DESIGN.md).

Children:
- [JSON adapter](Sources/RupaAgentCADBenchmarkJSONAdapter/DESIGN.md)
- [CAD CLI](Sources/RupaAgentCADBenchmarkCLI/DESIGN.md)
- [Responsiveness baseline](Sources/RupaResponsivenessBaseline/DESIGN.md)
- [Baseline CLI](Sources/RupaResponsivenessBaselineCLI/DESIGN.md)
- [Fixture document](Sources/RupaResponsivenessFixtureDocument/DESIGN.md)
- [Fixture CLI](Sources/RupaResponsivenessFixtureDocumentCLI/DESIGN.md)

The performance and geometry-buffer executables remain in RupaKit because they
measure package-only evaluation counters and storage tuning APIs. Historical
measurements remain in [Baselines](Baselines/README.md).

## Responsibilities and Boundaries

This package owns JSON/CLI composition, responsiveness fixtures, and measurement
executables. The CAD runner/oracle stays in RupaKit because it consumes
package-only response reservations. This package consumes exported products
and owns no application state or alternative CAD authority. RupaKit never
depends on it.

## Related Designs

| Design | Relationship | Contract Used | Summary | Cautions |
|---|---|---|---|---|
| [System](../DESIGN.md) | parent | CADAPI-100 acceptance | Defines the required production route | Restoration is not signed-App acceptance evidence |
| [RupaKit](../RupaKit/DESIGN.md) | depends on | Public CAD, project, Agent, rendering APIs | Supplies production behavior | No internal or package-only API access |
| [CAD benchmark](../RupaKit/Sources/RupaAgentCADBenchmark/DESIGN.md) | depends on | Fixed catalog and exact oracle | Owns case semantics and execution | Historical unsupported results do not satisfy CADAPI-100 |

## Architecture

```text
Rupa App ------> RupaKit <------ RupaBenchmarks
                                  |-- CAD JSON adapter / CLI
                                  `-- responsiveness / fixture export
```

## Contracts and Invariants

- Restored CAD case IDs, targets, tolerances, oracle code, and JSON baselines are
  byte-identical to d10c7605's parent; package location does not change meaning.
- The fixed 100-case acceptance contract remains owned by the CAD benchmark
  design and system master. Neither package separation nor unsupported outcomes
  relax it.
- SwiftPM enforces a one-way dependency on RupaKit's public products.
- Rendering's package-local test instrumentation stays independent of this
  package to avoid a dependency cycle.
- RupaKit owns its performance and geometry-buffer benchmarks alongside their
  package-private contracts; separation must not widen production API visibility.
- The CAD runner and its exact-oracle tests remain in RupaKit so semantic
  responses use the real single-consumption reservation contract. No alternate
  encoder or public visibility expansion is introduced for package separation.

## Verification and Change Impact

Compare restored implementation and fixture bytes against Git history, validate
both package graphs, run catalog/digest and rejection tests, and replay the
hundred cases through the restored executor. CLI adapter tests verify error
mapping; fixture tests verify persisted source reload. Actual GPU execution and
signed-App responsiveness require Apple-platform integration tests; a pure
SwiftPM test run does not prove those paths. Recheck the system and RupaKit
designs whenever the public dependency boundary changes.

For the installed Swift 6.4.2-dev 2026-09-04 toolchain and macOS 27 SDK,
build with cross-import overlays enabled and the compiler's debug-type
round-trip assertion disabled. These are compiler invocation flags, not
production source changes or relaxed test assertions:

```sh
swift build --package-path RupaBenchmarks --build-tests -j 4 \
  -Xswiftc -Xfrontend -Xswiftc -enable-cross-import-overlays \
  -Xswiftc -Xfrontend -Xswiftc -disable-round-trip-debug-types
```

Run focused Swift Testing tests with an external timeout after building.
The `semanticDomainExecutesTheFixedHundredCasesThroughProductionAuthority`
test verifies all 100 restored cases through the in-process semantic executor;
it does not start the signed App or exercise authenticated HTTP.

### Restoration verification, 2026-09-21

- This package's test build succeeds with the flags above. RupaKit's CAD test
  target and two package-local performance executables also build.
- The restored fixed catalog, frozen public/internal digests, and physical
  candidate/oracle separation tests pass. No target, tolerance, or oracle is
  changed to accommodate a failure.
- The in-process hundred-case replay realizes 95 cases. SPH-001 through SPH-005
  are rejected before publication with `executionRejected`. The same failures
  occur through the JSON adapter and actual CLI process tests. This is not
  CADAPI-100 acceptance and must not be described as all tests passing.
- Of 121 tests in this tools package, 111 pass and 10 sphere-route tests fail:
  fixture persistence 4/4, responsiveness contracts 14/14, JSON adapter 62/67,
  CLI contracts/processes 31/36. These responsiveness tests prove offscreen
  contracts, not signed-App/GPU performance.
- Three RupaKit architecture-boundary tests pass. Geometry-buffer measurement
  executes four chunk sizes with zero copied view bytes; performance measurement
  executes all four create/edit workloads with three bodies and two iterations.
- Restoration preserves implementation bytes except the performance executable's
  deferred-artifact guards. The sphere test additionally prints existing route
  diagnostics on failure; its success assertion is unchanged.
