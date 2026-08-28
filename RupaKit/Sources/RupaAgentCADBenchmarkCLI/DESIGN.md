# RupaAgentCADBenchmarkCLI

## Purpose and Scope

`RupaAgentCADBenchmarkCLI` is the dedicated native executable that exchanges
one activated CAD benchmark case with an external Agent over vendor-neutral
JSON. It is a child of the [RupaKit package design](../../DESIGN.md), has no
child design, and depends on the sibling
[JSON adapter](../RupaAgentCADBenchmarkJSONAdapter/DESIGN.md). Its executable
product is `rupa-agent-cad-benchmark`; it does not add commands to `rupa`.

## Responsibilities and Boundaries

The executable owns only command-line parsing, selection of standard input or
one response file, standard output, and stable process exit status. The
`request` command emits candidate-visible context. The `evaluate` command
decodes one external response and evaluates it through the JSON candidate and
activated-case executor.

It does not own envelope semantics, fingerprints, benchmark activation,
candidate decision semantics, project authority, oracle logic, prompts, an LLM
SDK, MCP, networking, file persistence, or multi-case scheduling.

## Related Designs

| Design | Relationship | Contract Used | Summary | Cautions |
|---|---|---|---|---|
| [RupaKit package](../../DESIGN.md) | parent | executable product and target graph | Registers this isolated native tool. | It must not change `RupaCLI` or `RupaCLIKit`. |
| [JSON adapter](../RupaAgentCADBenchmarkJSONAdapter/DESIGN.md) | depends on | bounded input, request/response/evaluation envelopes, JSON candidate | Owns all machine-readable exchange meaning. | The executable cannot decode a second permissive schema. |
| [RupaAgentCADBenchmark](../RupaAgentCADBenchmark/DESIGN.md) | transitive dependency | activated executor and production/oracle result | Executes exactly one reviewed case. | The CLI cannot activate a catalog-only case. |

## Architecture

```mermaid
flowchart LR
    Args["ArgumentParser"] --> Command{"request | evaluate"}
    Command -->|request CASE| Context["Activated executor context"]
    Context --> Request["JSON request envelope -> stdout"]
    Command -->|evaluate --response PATH|-| Input["Bounded stdin/file input"]
    Input --> Adapter["Validated JSON candidate"]
    Adapter --> Execute["Activated executor"]
    Execute --> Result["Evaluation envelope -> stdout + exit status"]
```

The executable target depends on
`RupaAgentCADBenchmarkJSONAdapter` and Argument Parser. It has no dependency on
`RupaCLIKit`, `RupaAgentTransport`, an LLM SDK, or MCP.

## Contracts and Invariants

The command contract is:

```text
rupa-agent-cad-benchmark request <CASE-ID>
rupa-agent-cad-benchmark evaluate --response <PATH|->
```

`request` validates that the ID is in the activated twenty-eight-case set and emits
exactly one request-envelope JSON object to standard output. `evaluate` reads
exactly one candidate-response envelope from the selected file, or from
standard input when `-` is selected, then emits exactly one evaluation- or
error-envelope JSON object to standard output. Machine output never mixes logs
or human diagnostics into standard output. `--help` and argument-parser usage
remain human-readable process metadata and are not evaluation envelopes.

Exit status is stable and orthogonal to JSON decoding:

| Exit | Meaning |
|---:|---|
| `0` | Request emitted, or evaluation completed with `realized`. |
| `2` | A valid response was evaluated to a non-realized candidate outcome such as invalid submission, expected/unexpected unsupported, timeout, or cancellation. |
| `64` | CLI usage, malformed/oversize JSON, unsupported schema, inactive case, case mismatch, fingerprint mismatch, or invalid decision. |
| `70` | Production execution, oracle, infrastructure, cleanup, or unexpected internal failure invalidated evaluation. |

For every `evaluate` invocation whose arguments select an input source, the
tool attempts to emit a bounded evaluation or error envelope before exiting.
If runtime error encoding itself fails, the CLI emits the adapter-owned
canonical bounded infrastructure-error document rather than empty output.
It never prints a Swift error description, source snapshot, expected geometry,
feature identity, or private oracle diagnostic. It never retries a candidate
or production command.

## Runtime Flows

```mermaid
sequenceDiagram
    participant E as External Agent
    participant C as CLI
    participant J as JSON adapter
    participant B as Benchmark executor
    E->>C: request CASE-ID
    C->>B: candidateContext(caseID)
    B-->>C: public context
    C->>J: encode bounded request
    J-->>E: request JSON on stdout
    E->>C: evaluate + response JSON
    C->>J: bounded decode
    J-->>C: bound JSON candidate
    C->>B: evaluate candidate
    B-->>C: sanitized case result
    C->>J: encode evaluation
    J-->>E: one JSON object + stable exit
```

## State, Ownership, and Lifecycle

Each process invocation owns one argument parse, at most one bounded input
buffer, and at most one output envelope. No state survives process exit. The
benchmark module owns and cleans the controller/workspace/registration used by
evaluation. Output redirection or persistence is the caller's responsibility.

## Failure, Concurrency, and Constraints

The executable runs one case and one candidate response at a time. It does not
spawn concurrent case work, background readers, or detached tasks. Standard
input must reach EOF within the caller-owned process deadline; the byte ceiling
is enforced while reading. File open/read failures are stable input errors.
Once evaluation enters the benchmark, its existing deadline, cancellation, and
unconditional registration-cleanup contract remains authoritative. External
process termination is only a safety ceiling and is not evidence of in-process
cleanup. The CLI adds no hidden option or environment hook to inject lifecycle
failures. No failure falls back to the reference candidate or to direct source
mutation.

## Verification and Change Impact

Process-level tests build and invoke the actual executable and prove:

- `request` emits valid v1 JSON for an activated line, rectangle, REC-009
  inch/XZ case, REC-010 metre/XY case, REC-011 millimetre/YZ case, and REC-012
  millimetre/XY case, plus CIR-001...004, and rejects inactive `CIR-005`;
- JSON line, rectangle, and circle responses traverse the adapter, production
  controller, and exact category oracle and exit `0` with `realized`;
- a REC-009 JSON response preserves its public inch/XZ/centre values, traverses
  the unchanged rectangle production controller and exact oracle, and exits `0`;
- a REC-010 JSON response preserves its public metre/XY/centre values, traverses
  the unchanged rectangle production controller and exact oracle, and exits `0`;
- a REC-011 JSON response preserves its public millimetre/YZ/centre values,
  traverses the unchanged rectangle production controller and exact oracle, and
  exits `0`;
- a REC-012 JSON response preserves its public millimetre/XY/centre values,
  traverses the unchanged rectangle production controller and exact oracle, and
  exits `0`;
- wrong geometry is published once, rejected without retry, returned as a
  non-realized envelope, and exits `2`;
- malformed, oversize, unknown-schema, mismatched-fingerprint, and inactive
  responses exit `64` without publication;
- valid `unsupported` and `finish` decisions exit `2` with typed
  `invalidSubmission`, zero publication, and no fallback action;
- all emitted evaluation/error JSON is bounded and private-data free.

For `T12-REC-010`, the twenty-one-case command boundary remained the confirmed
fact until the case gate passed. That gate advanced `request` and `evaluate`
together to the executor-owned twenty-two-case prefix, proved an actual bounded
REC-010 metre/XY request and external response exit `0` with `realized` through
the unchanged rectangle production/oracle path, and proved REC-011 remained an
inactive-case exit `64`. It did not add a command, argument,
schema, hidden test hook, or fallback candidate.

`T12-REC-011` similarly advanced the executor-owned command boundary from
twenty-two to twenty-three after its case gate passed. Actual process tests emit
a bounded millimetre/YZ REC-011 request, evaluate an external exact response to
`realized`/exit `0` through the existing rectangle path, and reject
REC-012 as inactive with exit `64`. Commands, arguments, schema, and fallback
behavior remain unchanged.

`T12-REC-012` advanced the executor-owned command boundary from twenty-three to
twenty-four after its case gate passed. Actual process tests emit a bounded
millimetre/XY REC-012 request, evaluate an external exact response to
`realized`/exit `0` through the existing rectangle path, and reject CIR-001 as
inactive with exit `64`. REC-012 is the rectangle catalog terminus, so the CLI
does not recognize an invented REC-013 boundary. Commands, arguments, schema,
and fallback behavior remain unchanged.

`T12-CIR-001` advanced the executor-owned boundary from twenty-four to
twenty-five after its internal production/oracle gate passed. Actual process
tests emit a bounded 5 mm XY CIR-001 request, accept only the
candidate-response v2 circle discriminator, evaluate an external exact response
to `realized`/exit `0` through `createCircleSketch`, and reject CIR-002 as
inactive with exit `64`. A candidate-response v1 document is an unsupported-
schema exit `64`; request/evaluation/error envelopes, commands, arguments,
bounded I/O, exit mapping, and fallback behavior remain unchanged.

`T12-CIR-002` adds no command or transport behavior. Before its internal case
gate passed, the executable was bound to the exact twenty-five activated IDs
through CIR-001. The completed case advances `request` and `evaluate` together
to the executor-owned twenty-six-ID prefix, proves an actual bounded 12.5 mm XY
CIR-002 request and external candidate-response-v2 evaluation as `realized`/
exit `0` through `createCircleSketch`, and rejected CIR-003 as inactive at that gate with exit
`64`. The frozen twenty-five-request aggregate remains unchanged; schema,
arguments, byte limits, exit mapping, cleanup ownership, and fallback behavior
do not change.

`T12-CIR-003` adds no command or transport behavior. Before its internal case
gate passed, the executable was bound to the exact twenty-six activated IDs
through CIR-002. The completed case advances `request` and `evaluate` together to
the executor-owned twenty-seven-ID prefix, proved an actual bounded 25 mm XZ
CIR-003 request and external candidate-response-v2 evaluation as `realized`/
exit `0` through `createCircleSketch`, and rejected CIR-004 as inactive at that gate with exit
`64`. The frozen twenty-six-request aggregate remains unchanged; schema,
arguments, byte limits, exit mapping, cleanup ownership, and fallback behavior
do not change.

### CIR-004 through CIR-012 sequential process boundary

The executable follows the benchmark-owned [circle case matrix](../RupaAgentCADBenchmark/DESIGN.md#cir-004-through-cir-012-case-matrix)
and the JSON adapter's ordered authority. Each case remains an individual gate
and commit. After that case's internal evidence passes, `request` and `evaluate`
advance together by exactly one ID, an actual bounded request and external
candidate-response-v2 document realize through `createCircleSketch` with exit
`0`, and the matrix's next ID remains inactive with exit `64`. The preceding
aggregate digest stays frozen and the new digest comes from observed request
bytes. CIR-012 advances the boundary to 36 and rejects ANG-001; the CLI does not
invent CIR-013. Commands, arguments, schema, byte limits, exit mapping, cleanup
ownership, and no-fallback behavior remain unchanged across all nine commits.

The explicit `evaluate --response <PATH|->` contract has no separate expected
case argument, so a case-mismatch process fixture cannot be constructed without
changing the command. Compositional tests instead prove that the adapter rejects
an explicitly mismatched expected case before publication and that the CLI maps
typed `caseMismatch` to exit `64`. Similarly, benchmark lifecycle tests own
deadline, cancellation, no-retry, and unconditional cleanup behavior, while CLI
mapping tests prove timeout/cancellation exit `2` and production execution,
oracle, infrastructure, and cleanup-invalidating outcomes exit `70`. Actual
process tests retain an external safety deadline but do not claim that killing a
process proves benchmark cleanup.

Changing command names, arguments, input source rules, JSON schema, result
classification, byte ceiling, or exit mapping requires updating this design,
the adapter design, process golden tests, and package product declaration.
