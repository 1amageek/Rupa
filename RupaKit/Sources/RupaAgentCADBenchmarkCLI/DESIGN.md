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

`request` validates that the ID is in the activated 83-case set and emits
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
  millimetre/XY case, the complete CIR-001...012 category, ANG-001...016, and
  BOX-001...012, `CYL-001...008`, `CON-001...008`, and `TRN-001...003`, and rejects inactive `TRN-004`;
- JSON line, rectangle, circle, angle, BOX-001...012, CYL-001...008, CON-001...008, and TRN-001...003 transform responses traverse the adapter, production
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

### ANG-001 atomic-batch process boundary

ANG-001 advances the process authority to 37 reviewed IDs and
candidate-response v3. An actual bounded response with `kind: "angle"` executes
two ordered line commands through one production batch and exits `0` only after
the immutable source oracle reports `realized`. Candidate-response v1 and v2
are rejected before decision decoding, and ANG-002 was inactive at that historical
boundary with exit
`64`. Request/evaluation/error schemas, byte limits, exit mapping, cleanup, and
no-retry behavior are unchanged.

ANG-002 advances the process authority to 38 reviewed IDs without adding a
command or changing candidate-response v3. An actual bounded response with
`kind: "angle"` executes the translated 45-degree pair through the same
production atomic batch and immutable source oracle, while ANG-003 remains
inactive with exit `64`. The preceding 37-request aggregate remains frozen;
the new aggregate is measured from the exact emitted requests. Commands,
arguments, schemas, byte limits, exit mapping, cleanup, and no-retry behavior
remain unchanged.

ANG-003 advances the process authority to 39 reviewed IDs without adding a
command or changing candidate-response v3. An actual bounded response with
`kind: "angle"` executes the translated 60-degree pair through the same
production atomic batch and immutable source oracle, while ANG-004 remains
inactive with exit `64`. The preceding 38-request aggregate remains frozen;
the new aggregate is measured from the exact emitted requests. Commands,
arguments, schemas, byte limits, exit mapping, cleanup, and no-retry behavior
remain unchanged.

ANG-004 advances the process authority to 40 reviewed IDs without adding a
command or changing candidate-response v3. An actual bounded response with
`kind: "angle"` executes the translated 75-degree pair through the same
production atomic batch and immutable source oracle, while ANG-005 remains
inactive with exit `64`. The preceding 39-request aggregate remains frozen;
the new aggregate is measured from the exact emitted requests. Commands,
arguments, schemas, byte limits, exit mapping, cleanup, and no-retry behavior
remain unchanged.

ANG-005 advances the process authority to 41 reviewed IDs without adding a
command or changing candidate-response v3. An actual bounded response with
`kind: "angle"` executes the orthogonal 75/125 mm pair through the same
production atomic batch and immutable source oracle, while ANG-006 remains
inactive with exit `64`. The preceding 40-request aggregate remains frozen;
the new aggregate is measured from the exact emitted requests. Commands,
arguments, schemas, byte limits, exit mapping, cleanup, and no-retry behavior
remain unchanged.

ANG-006 advances the process authority to 42 reviewed IDs without adding a
command or changing candidate-response v3. An actual bounded response with
`kind: "angle"` executes the negative-X 90/150 mm, 105-degree pair through the
same production atomic batch and immutable source oracle, while ANG-007 remains
inactive with exit `64`. The preceding 41-request aggregate remains frozen;
the new aggregate is measured from the exact emitted requests. Commands,
arguments, schemas, byte limits, exit mapping, cleanup, and no-retry behavior
remain unchanged.

ANG-007 advances the process authority to 43 reviewed IDs without adding a
command or changing candidate-response v3. An actual bounded response with
`kind: "angle"` executes the translated 105/200 mm, 120-degree pair through
the same production atomic batch and immutable source oracle, while ANG-008
remains inactive with exit `64`. The preceding 42-request aggregate remains
frozen; the new aggregate is measured from the exact emitted requests.
Commands, arguments, schemas, byte limits, exit mapping, cleanup, and no-retry
behavior remain unchanged.

ANG-008 advances the process authority to 44 reviewed IDs without adding a
command or changing candidate-response v3. An actual bounded response with
`kind: "angle"` executes the origin 120/250 mm, 135-degree pair through the
same production atomic batch and immutable source oracle, while ANG-009 remains
inactive with exit `64`. The preceding 43-request aggregate remains frozen;
the new aggregate is measured from the exact emitted requests. Commands,
arguments, schemas, byte limits, exit mapping, cleanup, and no-retry behavior
remain unchanged.

ANG-009 advances the process authority to 45 reviewed IDs without adding a
command or changing candidate-response v3. An actual bounded response with
`kind: "angle"` executes the translated 135/300 mm, 150-degree pair through
the same production atomic batch and immutable source oracle, while ANG-010
remains inactive with exit `64`. The preceding 44-request aggregate remains
frozen; the new aggregate is measured from the exact emitted requests.
Commands, arguments, schemas, byte limits, exit mapping, cleanup, and no-retry
behavior remain unchanged.

ANG-010 advances the process authority to 46 reviewed IDs without adding a
command or changing candidate-response v3. An actual bounded response with
`kind: "angle"` executes the negative-placement 150/350 mm, 165-degree pair
through the same production atomic batch and immutable source oracle, while
ANG-011 remains inactive with exit `64`. The preceding 45-request aggregate
remains frozen; the new aggregate is measured from the exact emitted requests.
Commands, arguments, schemas, byte limits, exit mapping, cleanup, and no-retry
behavior remain unchanged.

ANG-011 advances the process authority to 47 reviewed IDs without adding a
command or changing candidate-response v3. An actual bounded response with
`kind: "angle"` executes the canonical XZ +Y-normal 30/60 mm, 45-degree pair
through the same production atomic batch and immutable source oracle, while
ANG-012 remains inactive with exit `64`. The preceding 46-request aggregate
remains frozen; the observed 47-request aggregate is
`08a9f3fa73e242fe7116dfb904e5d254fabe3a1cb61c2004021e239f42cde3de`, measured
from the exact emitted requests.
Commands, arguments, schemas, byte limits, exit mapping, cleanup, and no-retry
behavior remain unchanged.

ANG-012 advances the process authority to 48 reviewed IDs without adding a
command or changing candidate-response v3. An actual bounded response with
`kind: "angle"` executes the canonical YZ +X-normal 40/100 mm, 60-degree pair
through the same production atomic batch and immutable source oracle, while
ANG-013 remains inactive with exit `64`. The preceding 47-request aggregate
remains frozen; the new aggregate is measured from the exact emitted requests.
Commands, arguments, schemas, byte limits, exit mapping, cleanup, and no-retry
behavior remain unchanged.

ANG-013 advances the process authority to 49 reviewed IDs without adding a
command or changing candidate-response v3. An actual bounded response with
`kind: "angle"` executes the canonical XZ +Y-normal 50/150 mm, 90-degree pair
through the same production atomic batch and immutable source oracle, while
ANG-014 remains inactive with exit `64`. The preceding 48-request aggregate
remains frozen; the new aggregate is measured from the exact emitted requests.
Commands, arguments, schemas, byte limits, exit mapping, cleanup, and no-retry
behavior remain unchanged.

ANG-014 advances the process authority to 50 reviewed IDs without adding a
command or changing candidate-response v3. An actual bounded response with
`kind: "angle"` executes the canonical YZ +X-normal 75/225 mm, 120-degree pair
through the same production atomic batch and immutable source oracle, while
ANG-015 remains inactive with exit `64`. The preceding 49-request aggregate
remains frozen; the new aggregate is measured from the exact emitted requests.
Commands, arguments, schemas, byte limits, exit mapping, cleanup, and no-retry
behavior remain unchanged.

ANG-015 advances the process authority to 51 reviewed IDs without adding a
command or changing candidate-response v3. An actual bounded response with
`kind: "angle"` executes the canonical XZ +Y-normal 100/300 mm, 135-degree pair
through the same production atomic batch and immutable source oracle, while
ANG-016 remains inactive with exit `64`. The preceding 50-request aggregate
remains frozen; the new aggregate is measured from the exact emitted requests.
Commands, arguments, schemas, byte limits, exit mapping, cleanup, and no-retry
behavior remain unchanged.

ANG-016 advances the process authority to 52 reviewed IDs without adding a
command or changing candidate-response v3. An actual bounded response with
`kind: "angle"` executes the canonical YZ +X-normal 125/375 mm, 150-degree pair
through the same production atomic batch and immutable source oracle, while
BOX-001 remains inactive with exit `64`. The preceding 51-request aggregate
`8a5baed7294693f150ce8e67494112f521b0667bfe1d4f6e45db0661e83d6f07` remains
frozen; the observed 52-request aggregate is
`53836e6352b776f1b2a0eccd81cc17d7046a489782a5ad678236d920e36f8a7a`. Commands,
arguments, schemas, byte limits, exit mapping, cleanup, and no-retry behavior
remain unchanged.

### BOX-001 through BOX-012 process boundary

BOX adds no CLI command. `request <BOX-ID>` emits the same bounded request v1;
`evaluate --response <PATH|->` accepts the adapter-owned candidate-response v4
that carries the benchmark-owned `solid` / `box` discriminators. BOX-001 must
prove the complete actual process route for a 10 × 10 × 10 mm box at the world
origin and must reject candidate-response v1 through v3 with input exit `64`.
Each following BOX case reuses the command and schema, proves its exact public
unit/dimensions/lower-corner response through the production controller and
source/B-Rep oracle, and advances process authority by one only after its case
gate passes. A valid wrong box exits `2` after one publication and no retry;
decode, schema, fingerprint, and inactive-ID failures exit `64`; benchmark
infrastructure or cleanup-invalidating failures retain exit `70`.

The ordered process boundary advances from 52 IDs through 64, preserving each
immediately preceding aggregate and freezing the emitted aggregate after every
case. The next lexical BOX ID remains inactive at each intermediate gate;
after BOX-012, `CYL-001` is inactive. Actual process evidence covers both file
and standard-input evaluation without exposing private dimensions, topology
predicates, source identities, or diagnostics. The 65,536-byte bound, one-JSON
stdout rule, exit mapping, request/evaluation/error schemas, and generic `rupa`
CLI remain unchanged.

BOX-001 preserves the frozen 52-request prefix
`53836e6352b776f1b2a0eccd81cc17d7046a489782a5ad678236d920e36f8a7a` and
observes the 53-request aggregate
`dd12c2cc346e37ec4f3dcecb396aa46bcfe69a82923a41041c36739b826d0b79`.
BOX-002 preserves that frozen 53-request aggregate and observes the 54-request
aggregate
`36bf68952c6a605df9e9bb4187929752ee42317f0a45506f9847bc265ac065ec`, and
executes a v4 translated 25 × 25 × 25 mm solid/box response at lower corner
(20, -20, 0) mm through the production controller.
BOX-003 preserves that frozen 54-request aggregate and observes the 55-request
aggregate
`74353ca8a790b520689404973dbc370b59ec77f50ec81ac3a48c4387b94862c3`, and
executes a v4 50 × 30 × 20 mm solid/box response at lower corner
(-25, 15, 5) mm through the production controller.
BOX-004 preserves that frozen 55-request aggregate and observes the 56-request
aggregate
`dc4c6fa1f96ae4181f54d48b34ae77b95d2548bc90935a3c7f0d7c51743efd9a`, and
executes a v4 100 × 50 × 75 mm solid/box response at lower corner
(0, 0, -25) mm through the production controller.
BOX-005 preserves that frozen 56-request
aggregate, observes the 57-request aggregate
`a7ae81207efbb6d315d2a11b61f7cbfa17d997e59ca74db7404c310bbecc24bb`, and
executes a v4 250 × 100 × 125 mm solid/box response at lower corner
(-125, -50, 0) mm through the production controller.

BOX-006 preserves that frozen 57-request aggregate, observes the 58-request
aggregate `1f0ecb07744e6525d6e68df789fb529ff3ad91220ff515603ea26a2f123d88d9`, and executes
a v4 0.1 × 0.05 × 0.025 m solid/box response at lower corner (0, 0, 0) m
through the production controller.

BOX-007 preserves that frozen 58-request aggregate, observes the 59-request
aggregate `22a57a1631712e9cc4cac3a50c5d2886909e804d2e44338b15911637318b74be`, and executes
a v4 1 × 2 × 3 inch solid/box response at lower corner (-1, -1, 0) inches
through the production controller.

BOX-008 preserves that frozen 59-request aggregate, observes the 60-request aggregate
`6f7467cbe5f511521c5a1ba79811fb38fc60a9f77c8585a1950eff7ea9033f81`, and executes
a v4 300 × 300 × 300 mm solid/box response at lower corner (100, 100, 100) mm
through the production controller.

BOX-009 preserves that frozen 60-request aggregate and observes the 61-request aggregate
`01837d577b9eaecc860279b474e8190c852777cf359910ced4196a1ca5c2e403`, and executes
a v4 12 × 12 × 12 mm solid/box response at lower corner (-12, 0, 0) mm through
the production controller.

BOX-010 preserves that frozen 61-request
aggregate, observes the 62-request aggregate
`7cce27a557abbfed9b6d8f1f020e14fff0b366497b79373071c7df625aa2078b`, and executes a
v4 400 × 200 × 50 mm solid/box response at lower corner (0, -100, 50) mm
through the production controller.

BOX-011 preserves that frozen 62-request
aggregate, observes the 63-request aggregate as
`404f138058b2e8826a582a2f957ffc6fae0174ef4a11b6f0820dccb14378917a`, and executes
a v4 0.5 × 0.5 × 0.5 m cube
response at lower corner (-0.25, -0.25, 0) m through the production controller.
The same numeric values and origin submitted in centimetres are rejected after
one publication without retry, zero width is rejected before publication, and
BOX-012 is the next reviewed case.

BOX-012 is the BOX-category completion boundary: it preserves that frozen 63-request
aggregate `404f138058b2e8826a582a2f957ffc6fae0174ef4a11b6f0820dccb14378917a`,
observes the 64-request aggregate as
`e7f1f8084f0c61855d28fe7e7e28a0860eba3ab6993ae5b9859d28448948618c`, and executes
a v4 75 × 125 × 175 mm solid/box
response at lower corner (25, 25, -75) mm through the production controller.
The same dimensions at z = -50 mm are rejected after one publication without
retry, zero depth is rejected before publication, and this is the verified
64-ID BOX-category completion boundary.

### CYL-001 process contract

CYL-001 adds no CLI command. After its internal production/oracle gate passes,
`request CYL-001` emits the existing bounded request v1 and
`evaluate --response <PATH|->` consumes candidate-response v5 with the
benchmark-owned `solid` / `cylinder` discriminator. The v5 response preserves
base centre (0, 0, 0) mm, +Z axis, radius 5 mm, and depth 20 mm, then traverses
the adapter, `ProjectAgentCommandController`, production
`createExtrudedCircle`, and exact source/B-Rep oracle. File and standard-input
evaluation exit `0` with `realized`; radius 6 mm exits `2` after one publication
without retry; malformed, v1-through-v4, binding, and inactive-ID inputs exit
`64`. CYL-002 remains inactive.

The process boundary advances from 64 to exactly 65 IDs while preserving the
64-request aggregate
`e7f1f8084f0c61855d28fe7e7e28a0860eba3ab6993ae5b9859d28448948618c`.
The observed 65-request aggregate is
`ad9d6ca086b3be46bcd2d778eb22beaa3b506a4f84216e0195f11aafbbef19e0`. CLI
output remains one bounded private-free JSON document; timeout, cancellation,
oracle, infrastructure, and cleanup classifications retain the existing
compositional benchmark/CLI ownership and exit mapping. Generic `rupa`, the
65,536-byte ceiling, and request/evaluation/error schemas do not change.

### CYL-002 process contract

CYL-002 adds no CLI command. `request CYL-002` emits bounded request v1 and
`evaluate --response <PATH|->` consumes the existing candidate-response v5
`solid/cylinder` action with base centre (25, -25, 0) mm, +X axis, radius 10 mm,
and depth 50 mm. File or stdin evaluation traverses the adapter, production
`createExtrudedCircle` controller route, and immutable oracle and exits `0`
with `realized`. The +Z-axis mismatch exits `2` after one publication without
retry; malformed, binding, and inactive inputs retain exit `64`. Authority
advances 65→66 only after the internal gate, preserves the frozen 65-request
aggregate, freezes the observed 66-request aggregate, and leaves CYL-003
inactive. Commands, schemas, bounds, privacy, one-JSON stdout, and exit mapping
remain unchanged.

### CYL-003 process contract

CYL-003 adds no CLI command. `request CYL-003` emits bounded request v1 and
`evaluate --response <PATH|->` consumes the existing candidate-response v5
`solid/cylinder` action with base centre (-50, 20, 10) mm, +Y axis, radius
25 mm, and depth 100 mm. File or stdin evaluation traverses the adapter,
production `createExtrudedCircle` controller route, and immutable oracle and
exits `0` with `realized`. The +Z-axis mismatch exits `2` after one publication
without retry; malformed, binding, and inactive inputs retain exit `64`.
Authority advances 66→67 only after the internal gate, preserves the frozen
66-request aggregate, freezes the observed 67-request aggregate, and leaves
CYL-004 inactive. Commands, schemas, bounds, privacy, one-JSON stdout, and exit
mapping remain unchanged.

### CYL-004 process contract

CYL-004 adds no CLI command. `request CYL-004` emits bounded request v1 and
`evaluate --response <PATH|->` consumes the existing candidate-response v5
`solid/cylinder` action with base centre (0, 0, -100) mm, -Z axis, radius 50 mm,
and depth 250 mm. File or stdin evaluation traverses the adapter, production
`createExtrudedCircle` controller route, and immutable oracle and exits `0`
with `realized`. The +Z-axis reversal exits `2` after one publication without
retry; malformed, binding, and inactive inputs retain exit `64`. Authority
advances 67→68 only after the internal gate, preserves the frozen 67-request
aggregate, freezes the observed 68-request aggregate, and leaves CYL-005
inactive. Commands, schemas, bounds, privacy, one-JSON stdout, and exit mapping
remain unchanged.

### CYL-005 process contract

CYL-005 adds no CLI command. `request CYL-005` emits bounded request v1 and
`evaluate --response <PATH|->` consumes candidate-response v5 with base centre
(0, 0, 0) cm, XY-diagonal axis (0.707106781187, 0.707106781187, 0), radius 2 cm,
and depth 10 cm. File or stdin evaluation traverses the unchanged adapter,
production `createExtrudedCircle` controller route, and immutable oracle and
exits `0` with `realized`. The +X-axis substitute exits `2` after one
publication without retry; malformed, binding, and inactive inputs retain exit
`64`. Authority advances 68→69 only after the internal gate, preserves the
frozen 68-request aggregate, freezes the observed 69-request aggregate, and
leaves CYL-006 inactive. Commands, schemas, bounds, privacy, one-JSON stdout,
and exit mapping remain unchanged.

### CYL-006 process contract

CYL-006 adds no CLI command. `request CYL-006` emits bounded request v1 and
`evaluate --response <PATH|->` consumes candidate-response v5 with base centre
(-0.1, 0.05, 0) m, YZ-diagonal axis (0, 0.707106781187, 0.707106781187), radius
0.05 m, and depth 0.2 m. File or stdin evaluation traverses the unchanged
adapter. Process authority advances to 70 after swift-CAD commit
`1b46681fb97a8cb04f66a1d6dc87b0f519025baa` corrects the oblique p-curve and
file/stdin evaluation traverses the production
`createExtrudedCircle` controller route and immutable oracle and exits `0` with
`realized`. The +Y-axis substitute exits `2` after one
publication without retry; malformed, binding, and inactive inputs retain exit
`64`. Authority advances 69→70 only after the internal gate, preserves the
frozen 69-request aggregate, freezes the 70-request aggregate
`88afcea2f1db7041f6093c9784f4e37eefcbceba28ec12497656ca21ef92a462`.
At CYL-006 completion, CYL-007 remained inactive. Commands, schemas, bounds, privacy, one-JSON stdout,
and exit mapping remain unchanged.

### CYL-007 process contract

CYL-007 adds no CLI command. `request CYL-007` emits bounded request v1 and
`evaluate --response <PATH|->` consumes candidate-response v5 with base centre
(2, 3, -1) inch, axis (-1, 0, 0), radius 1 inch, and depth 4 inch. File and
stdin evaluation must traverse the unchanged adapter, production
`createExtrudedCircle` controller route, and immutable oracle and exit `0` with
`realized`. The same numeric millimetre substitute exits `2` after one
publication without retry; malformed, binding, and inactive inputs retain exit
`64`. Process authority remains 70 until the internal gate succeeds, preserves
the frozen 70-request aggregate
`88afcea2f1db7041f6093c9784f4e37eefcbceba28ec12497656ca21ef92a462`, then
freezes the 71-request aggregate as
`f4960441dea3fe2dc3984b3c093d8a77699990a7f5e055c5a300cf09133baf5d`.
At CYL-007 completion, CYL-008 remained inactive. Commands,
schemas, bounds, privacy, one-JSON stdout, and exit mapping remain unchanged.

### CYL-008 process contract

CYL-008 adds no CLI command. `request CYL-008` emits bounded request v1 and
`evaluate --response <PATH|->` consumes candidate-response v5 with base centre
(100, 100, 100) mm, raw XYZ axis
(0.57735026919, 0.57735026919, 0.57735026919), radius 75 mm, and depth 150 mm.
File and stdin evaluation must traverse the unchanged adapter, production
`createExtrudedCircle` controller route, and immutable oracle and exit `0` with
`realized`. The equal-length Z-negated axis substitute exits `2` after one
publication without retry; malformed, binding, and inactive inputs retain exit
`64`. Process authority remains 71 until the internal gate succeeds, preserves
the frozen 71-request aggregate
`f4960441dea3fe2dc3984b3c093d8a77699990a7f5e055c5a300cf09133baf5d`, then
freezes the 72-request aggregate as
`842be9af6961688359198c5d7cda9d8134c36e9a07d56cbf5fe1e4b409cc9cea`.
At the CYL-008 process gate, CON-001 remained inactive pending its reviewed
foundation. Commands, schemas, bounds, privacy, one-JSON stdout,
and exit mapping remain unchanged.

### CON-001 process contract

CON-001 adds no CLI command or argument. `request CON-001` emits the bounded
request v1 public context. `evaluate --response <PATH|->` consumes
candidate-response v6 carrying the exact coincident relation and two public XY
millimetre lines, then traverses the adapter, activated executor, production
`ProjectAgentCommandController`/`createSketch` transaction, and immutable
source-relation oracle. File and stdin evaluation of the exact external
response exit `0` with one `realized` JSON document.

The published wrong-first-start response exits `2` after exactly one
publication without retry. A response with no unique shared endpoint exits `2`
without publication; candidate-response v1 through v5 and malformed input exit
`64`; at CON-001 completion, inactive `CON-002` requests also exited `64`.
Authority advances 72→73 only after the
internal gate, preserves the frozen 72-request aggregate
`842be9af6961688359198c5d7cda9d8134c36e9a07d56cbf5fe1e4b409cc9cea`,
and freezes the observed 73-request aggregate as
`efc4fac5670c6739132f6145b5fc18ed38f69b1fe5dfd9889e2b38603de75468`.
Existing byte limits,
private-free one-JSON stdout, failure exit mapping, and process safety deadline
remain unchanged.

### CON-002 process contract

CON-002 adds no CLI command or argument. `request CON-002` emits the bounded
request v1 public context and `evaluate --response <PATH|->` consumes the exact
candidate-response v6 `parallel` action through the adapter, activated executor,
production `ProjectAgentCommandController`/`createSketch` transaction, and
immutable source-relation oracle. File and stdin evaluation of the exact
external response exit `0` with one private-free `realized` JSON document.

The exact-geometry `perpendicular` substitute exits `2` after one publication
without retry, while a `parallel` response missing its second geometry exits `2`
before publication. Authority remains 73 until the internal gate passes,
preserves frozen aggregate
`efc4fac5670c6739132f6145b5fc18ed38f69b1fe5dfd9889e2b38603de75468`,
then freezes the 74-request aggregate
`6f9d75f040f25352de1a8b3b7b7cfa68fb5fe06118bf93875dfbf696ebc2b851`.
At CON-002 completion, `CON-003` remained inactive and
exited `64`. Candidate-response v6, byte limits, one-JSON stdout, privacy,
deadline ownership, and exit mapping remain unchanged.

### CON-003 process contract

CON-003 adds no CLI command or argument. `request CON-003` emits its bounded v1
public context; `evaluate --response <PATH|->` consumes the exact v6
`perpendicular` action through the adapter, activated executor, production
`ProjectAgentCommandController`/`createSketch` transaction, and immutable
source-relation oracle. Exact file and stdin responses exit `0` with one
private-free `realized` JSON document.

The exact-geometry `parallel` substitute exits `2` after one publication without
retry, and the zero-length first-line response exits `2` before publication.
Authority remains 74 until the internal gate passes, preserves aggregate
`6f9d75f040f25352de1a8b3b7b7cfa68fb5fe06118bf93875dfbf696ebc2b851`,
then freezes the 75-request aggregate
`9a9759ff74dbe5222940164edbbb60040f732453889fe2648ed0c2e205e6e69c`.
At CON-003 completion, `CON-004` remained inactive and
exited `64`. Candidate-response v6, bounded/private-free one-JSON output,
deadline ownership, and exit mapping remain unchanged.

### CON-004 process contract

CON-004 adds no CLI command or argument. `request CON-004` emits its bounded v1
public context; `evaluate --response <PATH|->` consumes the exact v6 unary
`horizontal` action through the adapter, activated executor, production
`ProjectAgentCommandController`/`createSketch` transaction, and immutable
source-relation oracle. Exact file and stdin responses exit `0` with one
private-free `realized` JSON document.

The same-line `vertical` substitute exits `2` after one publication without
retry, while a horizontal response containing a second line exits `2` before
publication. Authority remains 75 until the internal gate passes, preserves
aggregate
`9a9759ff74dbe5222940164edbbb60040f732453889fe2648ed0c2e205e6e69c`,
then freezes the 76-request aggregate
`8878fa7dc59023aba4097c833bcca24f793829df83d8ad42106c8efebb985b79`.
At CON-004 completion, `CON-005` remained inactive and exited `64`.
Candidate-response v6, bounded/private-free one-JSON output,
deadline ownership, and exit mapping remain unchanged.

### CON-005 process contract

CON-005 adds no CLI command or argument. `request CON-005` emits its bounded v1
public context; `evaluate --response <PATH|->` consumes the exact v6 unary
`vertical` action through the adapter, activated executor, production
`ProjectAgentCommandController`/`createSketch` transaction, and immutable
source-relation oracle. Exact file and stdin responses exit `0` with one
private-free `realized` JSON document.

The same-line `horizontal` substitute exits `2` after one publication without
retry, while a vertical response containing a second line exits `2` before
publication. Authority remains 76 until the internal gate passes and preserves
aggregate
`8878fa7dc59023aba4097c833bcca24f793829df83d8ad42106c8efebb985b79`.
The 77-request aggregate
`c4734be651136aa602367bbbc1ff1db68c5e933153146be1ca751325eca6f98e`
is frozen as a literal shared with executor and adapter evidence. At CON-005
completion, `CON-006` remained inactive and exited `64`.
Candidate-response v6, bounded/private-free one-JSON output, deadline
ownership, and exit mapping remain unchanged.

### CON-006 process contract

CON-006 adds no CLI command or argument. `request CON-006` emits its bounded v1
public context; `evaluate --response <PATH|->` consumes the exact v6 binary
`equalLength` action through the adapter, activated executor, production
`ProjectAgentCommandController`/`createSketch` transaction, and immutable
source-relation oracle. Exact file and stdin responses exit `0` with one
private-free `realized` JSON document.

The same-geometry `parallel` substitute exits `2` after one publication without
retry, while a response whose second line is zero-length exits `2` before
publication. Authority remains 77 until the internal gate passes and preserves
aggregate
`c4734be651136aa602367bbbc1ff1db68c5e933153146be1ca751325eca6f98e`.
The 78-request aggregate
`95be7c1009a42bc3f81b0a7df50bec09256829f6034a6a76b37d70271486e590`
is frozen as a literal shared with executor and adapter evidence. At CON-006
completion, `CON-007` remained inactive and exited `64`.
Candidate-response v6, bounded/private-free one-JSON output, deadline
ownership, and exit mapping remain unchanged.

### CON-007 process contract

CON-007 adds no CLI command or argument. `request CON-007` emits its bounded v1
public context; `evaluate --response <PATH|->` consumes the exact v6 binary
`concentric` action through the adapter, activated executor, production
`ProjectAgentCommandController`/`createSketch` transaction, and immutable
source oracle. Exact file and stdin responses exit `0` only after the private
oracle proves both the authored circles/relation and the expected derived
annular profile region; the CLI exposes neither derived-region expectations nor
source authority and emits one private-free `realized` JSON document.

The `equalRadius`/10 mm second-circle substitute exits `2` after one
publication without retry, while a response whose first radius is 0 mm exits
`2` before publication. Authority remains 78 until the internal gate passes
and preserves aggregate
`95be7c1009a42bc3f81b0a7df50bec09256829f6034a6a76b37d70271486e590`.
The 79-request aggregate
`d893db3650a26a276826b09dd4825d1f032d03a4faf11abf3e1d2d65caa13136`
is frozen as a literal shared with executor and adapter evidence. At CON-007
completion, `CON-008` remained inactive and exited `64`.
Candidate-response v6, bounded/private-free one-JSON output, deadline
ownership, and exit mapping remain unchanged.

### CON-008 process contract

CON-008 adds no CLI command or argument. `request CON-008` emits its bounded v1
public context; `evaluate --response <PATH|->` consumes the exact v6
`equalRadius` action through the adapter, activated executor, production
`ProjectAgentCommandController`/`createSketch` transaction, exact
authored-source oracle, and private two-disk derived-region oracle. Exact file
and stdin responses exit `0` with one private-free `realized` JSON document;
no profile index, selection identity, region geometry, tolerance, or private
expectation is emitted.

The `concentric`/shared-center substitute exits `2` after one publication
without retry, while a response whose second radius is 0 mm exits `2` before
publication. Authority remains 79 until the internal gate passes and preserves
aggregate
`d893db3650a26a276826b09dd4825d1f032d03a4faf11abf3e1d2d65caa13136`.
The 80-request aggregate
`91f68ea42c6e131263b499995637e9f9b7dbce64fcf441bdcdf385c9f341efb0`
is frozen as one literal shared with executor and adapter evidence. `TRN-001` remains inactive and exits `64`
until the transform category begins. Candidate-response v6,
bounded/private-free one-JSON output, command surface, deadline ownership, and
exit mapping remain unchanged.

### TRN-001 through TRN-003 current process boundary

The current executable authority is the exact ordered 83-case prefix
`LIN-001`...`LIN-012`, `REC-001`...`REC-012`, `CIR-001`...`CIR-012`,
`ANG-001`...`ANG-016`, `BOX-001`...`BOX-012`, `CYL-001`...`CYL-008`,
`CON-001`...`CON-008`, and `TRN-001`...`TRN-003`. `TRN-004`...`TRN-008` remain
inactive and are rejected with exit `64` by both `request` and `evaluate` before
production execution. The candidate-response schema is v7; v1...v6 are
rejected as unsupported schema.

`request TRN-001` through `request TRN-003` emit one bounded transform context. An
exact v7 response
from either a file or standard input exits `0` after the existing
`setSceneNodeTransform` production route and oracle realize the source. A
TRN-001 translation with x = 26 mm, TRN-002 wrong-order translation
`(-17.67766952966369, 17.67766952966369, 0)` mm, and TRN-003 wrong-order
translation `(0, -50, 0)` mm exit `2` as
`invalidSubmission` after one publication without retry; a zero rotation axis
exits `2` before publication. All output remains one bounded private-free JSON
object. The historical
80-request aggregate remains
`91f68ea42c6e131263b499995637e9f9b7dbce64fcf441bdcdf385c9f341efb0`, and the
actual ordered 81-request aggregate after TRN-001 is
`e4c0ad812c421428ed59c7dd2671922e9e1f667af3f574d0ea87a461e53aab82`; appending
the actual TRN-002 request freezes the 82-request aggregate as
`9ca519a087729b5aa46e549ef3ec6f903158a8aff159dce2bcce09182f0b46ef`;
appending the actual TRN-003 request freezes the 83-request aggregate as
`02a7bfa19eed2aa8cdef578058a97b48b5e88822840cbd23343590a8281b579a`.

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
