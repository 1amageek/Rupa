# CAD Benchmark Aggregate Execution

## Purpose and Scope

This component composes the 100 already-reviewed single-case execution paths
into one complete benchmark run. It is a child of the
[RupaAgentCADBenchmark module design](../DESIGN.md) and has no child design.
T12-I.1 owns serial replay and deterministic per-case regression evidence;
later T12-I work adds bounded scheduling, baselines, and canonical reporting
without changing the single-case JSON or CLI contract.

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
- T12-I.1 admits one case at a time. A missing, duplicate, invalid, cancelled,
  or failed execution aborts the attempt and cannot produce a report or
  baseline.
- Current reference execution produces 95 realized cases and five honest
  expected-unsupported sphere cases.

## Runtime Flows

```text
validate catalog and activation set
  -> for each manifest ID in lexical order
      -> build candidate from public context
      -> execute existing production/oracle path
      -> validate cleanup and normalize deterministic evidence
  -> require exactly 100 ordered results
  -> publish immutable complete attempt
```

## State, Ownership, and Lifecycle

Aggregate values are immutable. Each case retains only value evidence after
its existing category lifecycle has released controller, workspace, and
registration ownership. No live project object escapes a case.

## Failure, Concurrency, and Constraints

T12-I.1 has concurrency one. Aggregate errors are typed and preserve the
failing case when available. Partial values are discarded. Future bounded
parallelism must use structured tasks, drain every admitted child on failure or
cancellation, and keep performance measurement outside deterministic records.

## Verification and Change Impact

`CADBenchmarkSerialIntegrationTests` proves lexical 100-case production replay,
95/5 outcomes, complete cleanup, deterministic record validation, direct
single-case projection equality, and typed incomplete/invalid failure. Changes
to category result fields, activation, manifest order, lifecycle cleanup,
capability observation, or public result projection require this component and
the parent design to be rechecked.
