# Analysis Strategy

## Task Structure

The review uses four linked surfaces: declared product goal, normative requirements, executable implementation, and verification evidence. A capability is considered sufficient only when all four surfaces agree on scope and failure semantics.

## Key Layers and Categories

- Context
  - Product boundary and intended consumers
  - External format and platform constraints
- Situation
  - Package/module inventory
  - Declared capabilities
  - Existing tests and diagnostics
- Operation
  - Modeling/evaluation pipeline
  - Persistence and exchange paths
  - Validation and failure handling
- Problem
  - Requirement ambiguity
  - Capability gaps and constrained implementations
  - Verification gaps
- Issue
  - Architectural causes
  - Missing completion contracts
  - Scope estimation errors
- Solution
  - Requirement corrections
  - Prioritized implementation gates
- Outcome
  - Readiness classification
  - Residual risk and decision recommendation

## Decomposition Strategy

1. Structural decomposition by package product, target, public type, implementation service, and test target.
2. Contrastive analysis across claimed, implemented, tested, and production-ready support.
3. Causal tracing from observed gaps to requirement or architectural causes.
4. Risk decomposition by correctness, topology, numerical robustness, persistence, interoperability, concurrency, and operational quality.

## Evidence Report Design

The final report will expose:

- a capability verification matrix showing the four support levels;
- a requirement-quality matrix separating valid, ambiguous, contradictory, and missing completion criteria;
- a risk matrix ranking unimplemented or underestimated areas by user impact and evidence strength;
- an architecture flow connecting document IR, evaluation, topology, tessellation, and exchange;
- a prioritized action sequence with explicit exit criteria.

## Chartable Data Requirements

- Capability counts by support level and subsystem.
- Requirement counts by normative status and verification coverage.
- Gap counts by severity, subsystem, and confidence.
- Test evidence by target and quality dimension.
- Prioritized actions by impact, effort, dependency, and acceptance evidence.

## Revision History

- 2026-07-12: Initial strategy created from the user request and repository-wide structural scan.
- 2026-07-12: Split readiness into two decision surfaces: the narrow official pipeline and the strategic Rupa/Plasticity-class goal.
- 2026-07-12: Added standalone distribution, schema evolution, operation parity, external conformance, and resource-limit safety as release-level gates after evidence showed these were not covered by the box-centric acceptance criteria.
