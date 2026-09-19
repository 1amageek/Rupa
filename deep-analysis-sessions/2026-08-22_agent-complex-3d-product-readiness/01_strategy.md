# Analysis Strategy

## Decomposition

```mermaid
flowchart LR
    A[Goal and conformance contract] --> B[Package and ownership map]
    B --> C[Agent-to-geometry execution path]
    C --> D[Representative runtime verification]
    D --> E[Capability and release gates]
    E --> F[Readiness synthesis]
```

## Evidence policy

- Treat normative architecture and plans as requirements, not implementation evidence.
- Prefer executable paths and source implementations over declarations.
- Treat tests as behavioral evidence only when the current checkout builds and executes them.
- Keep prior test records as historical evidence, not current verification.
- Separate official machine metrics from engineering estimates.

## Hypotheses

| Hypothesis | Prior | Decisive observation |
|---|---:|---|
| The Agent path is only a mock surface | 0.35 | Follow mutation from transport through transaction and real evaluator. |
| Bounded mechanical workflows are implemented | 0.60 | Inspect sweep, revolve, loft, boolean integration tests and executor path. |
| The broad complex-product goal is achieved | 0.25 | Find conforming profiles and execute current release gates. |
| Reproducibility is a current blocker | 0.45 | Build the current package and inspect dependency revision/cleanliness. |

## Verification performed

- Source-level end-to-end tracing of Agent dispatch, capability invocation, batch transactions, command stack, evaluation, and CAD geometry publication.
- Static capability route count.
- swift-CAD capability ledger, public contract inventory, and goal-contract checks.
- Focused `xcodebuild test` attempt covering Agent modeling, Agent transactions, Agent contracts, CAD integration, and universal project evaluation.
- Current repository revision and worktree checks.

## Critical path

The critical path is reproducible integration -> one authoritative project transaction -> Core Precision CAD conformance -> Agent Variant conformance -> additional product domains.
