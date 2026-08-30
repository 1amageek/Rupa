# CAD Benchmark Aggregate Execution

## Purpose and Scope

This component composes the 100 already-reviewed single-case execution paths
into one complete benchmark run. It is a child of the
[RupaAgentCADBenchmark module design](../DESIGN.md) and has no child design.
T12-I.1 owns serial replay and deterministic per-case regression evidence.
T12-I.2 owns bounded scheduling, cancellation drain, noisy concurrency
measurement, and the measured execution policy. Later T12-I work adds
baselines and canonical reporting without changing the single-case JSON or CLI
contract.

## Responsibilities and Boundaries

The component owns manifest-ordered scheduling, complete-run validation,
timing-free regression records, run-level measurement, and typed aggregate
failure. It does not own CAD semantics, geometry truth, project mutation,
single-case activation order, candidate transport, JSON/CLI schema, or baseline
updates. Category runners and their exact oracles remain the only owners of
geometry correctness.

## Related Designs

| Design | Relationship | Contract Used | Summary | Cautions |
|---|---|---|---|---|
| [RupaAgentCADBenchmark](../DESIGN.md) | parent | activated executor, category runners, manifest, results | Supplies all single-case behavior composed here. | Executor category order differs from manifest lexical order. |
| [JSON adapter](../../RupaAgentCADBenchmarkJSONAdapter/DESIGN.md) | coordinates with | unchanged sanitized single-case result | External candidates continue to use one-case exchange only. | Aggregate evidence must not enter the reviewed wire. |
| [CLI](../../RupaAgentCADBenchmarkCLI/DESIGN.md) | coordinates with | unchanged single-case process contract | The CLI is not an aggregate scheduler. | No aggregate command or schema version is introduced. |

## Architecture

```text
catalog manifest lexical IDs
        -> bounded scheduler (maximum 1 or 2 admitted cases)
            -> reference runner
            -> detailed activated-case executor
                -> existing category runner
                    -> production controller and exact oracle
            -> timing-free regression record
            -> separate noisy measurement
```

## Contracts and Invariants

- A complete run uses exactly the manifest's 100 lexical IDs; activation is
  checked by count and set because its established category order is distinct.
- Public `CADActivatedCaseExecuting`, `CADCaseResult`, JSON, CLI, and
  candidate-response v8 remain unchanged.
- Every detailed execution validates its category result and completes cleanup
  before it can enter an aggregate result.
- Regression records exclude duration, generated identities, diagnostics, and
  private expected geometry. A category-unobserved count is `nil`, never a
  fabricated zero.
- A missing, duplicate, invalid, cancelled, or failed execution aborts the
  attempt and cannot produce a report or baseline.
- Current reference execution produces 95 realized cases and five honest
  expected-unsupported sphere cases.
- The scheduler admits only one or two cases and restores completion results to
  manifest lexical order. It uses structured child tasks and drains every
  admitted child after cancellation or the first fatal failure.
- Observed in-flight cases measure case lifetime through cleanup-complete
  evidence. The separately observed synchronous MainActor entry remains one;
  an in-flight peak of two is not evidence of parallel CAD-kernel execution.
- Three alternating measurements for concurrency one and two select two only
  when the median wall-time improvement exceeds the maximum range of either
  measurement group.
- The checked-in policy is concurrency one with a 38-second enforced whole-run
  deadline. One experiment selected two from serial measurements 16.972505291,
  17.149335042, and 16.936391958 seconds versus bounded-two measurements
  12.420638250, 11.784386250, and 11.799141167 seconds. The immediate integrated
  rerun selected one because bounded-two values 11.889465458, 16.730554708, and
  13.441079792 seconds varied more than the median improvement over serial
  values 17.375750500, 17.876906375, and 18.834590666 seconds. This failure to
  repeat selects the conservative serial policy; the 38-second deadline is
  twice the largest observed successful wall time rounded up. These wall times
  are noisy evidence and never enter deterministic records or reports.

## Runtime Flows

```text
validate catalog and activation set
  -> admit at most the configured one or two manifest IDs
      -> build candidate from public context
      -> execute existing production/oracle path
      -> validate cleanup and normalize deterministic evidence
      -> place completion at its manifest index
  -> require exactly 100 ordered results
  -> publish immutable complete attempt

cancel or first fatal failure
  -> cancel all admitted children
  -> drain every child
  -> require active cases = 0 and remaining registrations = 0
  -> return typed run failure without an attempt, report, or baseline
```

## State, Ownership, and Lifecycle

Aggregate values are immutable. Each case retains only value evidence after
its existing category lifecycle has released controller, workspace, and
registration ownership. No live project object escapes a case.

## Failure, Concurrency, and Constraints

Aggregate errors are typed and preserve the failing case when available.
Partial values are discarded. Bounded parallelism uses structured tasks,
drains every admitted child on failure or cancellation, and keeps performance
measurement outside deterministic records. The whole-run deadline is twice the
largest successful wall time rounded up to seconds and must remain below the
sum of the 100 per-case deadlines. The policy runner races the bounded run with
that deadline, cancels and drains the case group when it expires, and uses
drain evidence from either a cancelled run or a run that completed at the
deadline boundary. Registration count comes from the lifecycle registration
owner rather than an assumed value. A cancellation guard after the final drain
prevents late publication.

## Verification and Change Impact

`CADBenchmarkSerialIntegrationTests` proves lexical 100-case production replay,
95/5 outcomes, complete cleanup, deterministic record validation, direct
single-case projection equality, and typed incomplete/invalid failure. Changes
to category result fields, activation, manifest order, lifecycle cleanup,
capability observation, or public result projection require this component and
the parent design to be rechecked. `CADBenchmarkConcurrencyTests` proves
bounded admission, lexical deterministic equality, observed in-flight and
MainActor-entry concurrency, fatal/cancellation drain, the six-run selection
rule, and the checked-in deadline.
