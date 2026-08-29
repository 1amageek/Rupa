# RupaAgentCADBenchmarkJSONAdapter

## Purpose and Scope

`RupaAgentCADBenchmarkJSONAdapter` is the vendor-neutral JSON exchange boundary
between an external Agent process and the activated-case executor owned by
`RupaAgentCADBenchmark`. It is a native SwiftPM library target and a child of the
[RupaKit package design](../../DESIGN.md). It has no child design. The sibling
[benchmark CLI](../RupaAgentCADBenchmarkCLI/DESIGN.md) supplies process arguments
and standard streams; this target owns the JSON meaning used by that process.

The adapter is limited to the fifty-two reviewed cases `LIN-001`...`LIN-012`,
`REC-001`...`REC-012`, `CIR-001`...`CIR-012`, and `ANG-001`...`ANG-016`. It does not
activate a catalog case and does not make the remaining target specifications
executable.

## Responsibilities and Boundaries

The target owns:

- versioned request, candidate-response, evaluation-result, and stable-error
  envelopes;
- the canonical fingerprint of one candidate-visible `CADCandidateContext`;
- schema, case-ID, fingerprint, and decision validation before a decision can
  enter benchmark execution;
- a public Data-based evaluation entry that performs the fixed bounded decode
  before any executor call, plus an internal `CADCandidateProtocol` bridge that
  returns the validated external decision only when the executor presents the
  exact matching live public context;
- bounded JSON reads from either standard input or one explicitly selected
  local file, plus bounded deterministic JSON encoding and the canonical
  prevalidated infrastructure-error document used when runtime encoding itself
  fails.

It does not own challenge meaning, decision/action meaning, activated-case
selection, a project/workspace, command routing, an oracle, private expected
geometry, scoring, process arguments, network I/O, an LLM SDK, MCP, or the
general-purpose `rupa` CLI. It never imports an internal oracle type and cannot
construct a benchmark result without calling the public activated-case
executor.

## Related Designs

| Design | Relationship | Contract Used | Summary | Cautions |
|---|---|---|---|---|
| [RupaKit package](../../DESIGN.md) | parent | target dependency direction | Places this target above the benchmark and below the dedicated executable. | No production authority target may depend on this adapter. |
| [RupaAgentCADBenchmark](../RupaAgentCADBenchmark/DESIGN.md) | depends on | public candidate context, explicit decision codecs, activated-case executor, sanitized case result | Supplies all CAD and benchmark meaning. | The adapter must not reproduce public action semantics in parallel DTOs or expose internal evidence. |
| [Benchmark CLI](../RupaAgentCADBenchmarkCLI/DESIGN.md) | used by | bounded decode/encode and envelope evaluation | Provides the process entry that external Agents invoke. | Process concerns remain in the executable target. |

## Architecture

```mermaid
flowchart LR
    PublicContext["CADCandidateContext\npublic values only"] --> Canonical["Canonical context payload\nSHA-256 fingerprint"]
    Canonical --> Request["Request envelope v1"]
    External["External Agent"] --> Response["Candidate response envelope v3"]
    Request --> External
    Response --> Validate["Public Data entry\nbounded decode + validation"]
    Validate --> Candidate["Internal JSON candidate\nCADCandidateProtocol"]
    Candidate --> Executor["Activated-case executor"]
    Executor --> Evaluation["Sanitized evaluation envelope v1"]
    Private["Private expectation / oracle"] -. "not importable or encodable" .-> Response
```

Dependency direction is
`RupaAgentCADBenchmark -> RupaAgentCADBenchmarkJSONAdapter ->
RupaAgentCADBenchmarkCLI`; the arrows denote consumption by the item on the
right. The adapter has no dependency on `RupaCLIKit`.

## Contracts and Invariants

### Envelope contract

The adapter owns four top-level envelopes. Every envelope is one UTF-8 JSON
object, rejects unknown schema versions, and validates all required fields.

| Envelope | Required fields | Meaning |
|---|---|---|
| request v1 | `schema`, `caseID`, `contextFingerprint`, `context` | Exact public context offered to the external Agent. |
| candidate response v3 | `schema`, `caseID`, `contextFingerprint`, `decision` | One decision, including the activated circle or angle action, returned by the JSON candidate. |
| evaluation v1 | `schema`, `caseID`, `contextFingerprint`, exactly one of `result` or `error` | Sanitized terminal outcome returned by the executable. |
| error v1 | `schema`, `code`, `message`; optional `caseID` | Stable private-free failure before a case is known, or a case-bound failure when a validated ID is available. |

The benchmark-owned `CADBenchmarkCaseID` is a validated single-value string in
every position, including top-level `caseID`, `context.challenge.id`, and
`result.id`. The adapter consumes that scalar contract directly and does not
wrap or mirror it. The former synthesized `{ "rawValue": ... }` object is
rejected before context fingerprinting or evaluation; v1 has no legacy
fallback because no external adapter release used that shape.

The candidate response carries the existing benchmark-owned
`CADCandidateDecision`. The benchmark's associated-value enums
`CADCandidateDecision`, `CADCandidateAction`, `CADAutomationAction`, and
`CADSketchAction` use explicit `kind` discriminators and named payload fields.
`CADOutputRoleSelector` does the same for the transitive `finish` payload. The
adapter does not introduce flat line/rectangle DTOs that would duplicate those
semantics. Because the benchmark package is unreleased and the old synthesized
enum encoding had only round-trip tests, the initial candidate-response v1
adopted the explicit shape without a compatibility decoder; golden JSON and
rejection tests froze that decision before the CLI was released. CIR-001 adds the closed
`CADSketchAction` discriminator `circle`; candidate-response advances to v2 and
v1 is rejected without fallback. Request, evaluation, and error envelopes stay
at v1, and the context fingerprint is unchanged.

ANG-001 adds the explicit `angle` discriminator with two ordered endpoint
pairs. Candidate-response advances to v3; v1 and v2 are rejected by the schema
guard before decision decoding. Request, evaluation, error, and fingerprint
schemas remain unchanged.

BOX-001 adds `CADAutomationAction.kind: "solid"` carrying
`CADSolidAction.kind: "box"` with a name, lower-corner origin, width, depth,
and height. Candidate-response advances to v4; v1, v2, and v3 are rejected by
the schema guard before decision decoding. Request, evaluation, error,
fingerprint, manifest/catalog, expectation, capability, and tolerance schemas
remain unchanged. No adapter-owned box DTO duplicates the benchmark action.

Public production evaluation accepts candidate-response `Data`, not a decoded
envelope or candidate value. It always applies the fixed 65,536-byte decode
before constructing the internal typed response and candidate bridge. Typed
evaluation and candidate construction remain module-internal test/composition
seams, so a caller cannot construct a large in-memory response and bypass the
JSON input authority.

The activated fifty-two cases accept one action decision. `unsupported` and
`finish` remain valid protocol values but are not converted to successful
actions; the T12-XA-A executor contract projects either as typed
`invalidSubmission` without publication. Multi-round continuation is not added
here, and the adapter never substitutes a reference action.

### Public-context fingerprint

`contextFingerprint` is lowercase SHA-256 over the UTF-8 bytes formed by the
domain separator `rupa.agent-cad-benchmark.public-context.v1` followed by a
newline and the deterministic JSON encoding of `CADCandidateContext` using
sorted keys and unescaped slashes. The request envelope itself is excluded to
avoid self-reference. The adapter emits the value; an external vendor need
only return it unchanged.

During evaluation, `CADJSONCandidate.decide(for:)` recomputes the fingerprint
from the live context supplied by the production harness and requires exact
schema, case ID, and fingerprint equality before returning the decision. A
mismatch is a typed adapter failure and creates no workspace publication. No
fallback accepts a response by case ID alone.

### Bounds and stable failures

One request, response, or evaluation document is limited to 65,536 bytes. A
reader consumes chunks only until `limit + 1`, rejects oversize before JSON
decode, and does not use an unbounded whole-file convenience API. The bound is
accepted only when the largest encoded activated request/response fixture is
measured below one quarter of it; changing the envelope or activated context
requires repeating that evidence or versioning the bound.

Only standard input or one explicit local file path is supported. URLs,
network reads, directories, multiple concatenated JSON values, trailing
non-whitespace bytes, and silent encoding repair are rejected. Stable error
codes distinguish malformed UTF-8/JSON, oversize input, unsupported schema,
inactive case, case mismatch, fingerprint mismatch, invalid decision,
candidate rejection, timeout/cancellation, oracle/infrastructure failure, and
output overflow. Error envelopes contain no private expectation, observed
source geometry, feature identity, or oracle diagnostic text.
The adapter owns one guaranteed infrastructure-error document whose bytes equal
the normal deterministic encoding of error v1, remain within the same bound,
and decode to that exact envelope. The CLI may use it only after runtime error
encoding fails, so a machine command never substitutes empty output for its
terminal JSON error.

Activation availability is read only from the benchmark executor. REC-009 did
not change envelope v1, fingerprint v1, the benchmark catalog, or the
expectation contract. Its aggregate fixture proved that the original twenty
request bytes and historical digest were unchanged, froze the then-current
twenty-one-request aggregate, and kept the largest request/response below one
quarter of the existing bound. REC-010 was its typed inactive boundary. The
completed T12-XA and REC-009 digests remain historical evidence and are not
presented as current authority.

`T12-REC-010` is an additive activation transition, not a schema change. Before
its vertical gate passed, the adapter was limited to the twenty-one-case prefix
through `REC-009`. The gate derived the exact ordered twenty-two-case prefix
from the executor, proved that the historical first-twenty and REC-009 twenty-
one-request aggregates still matched their frozen digests, and froze a new
digest over the actual twenty-two bounded requests. An exact public metre/XY
REC-010 response traversed the unchanged rectangle production route and oracle;
`REC-011` remained a typed inactive failure before evaluation. Envelope v1,
fingerprint v1, and the existing byte ceiling remained unchanged.

`T12-REC-011` is the next additive activation. Before its gate passed, the
executor-owned adapter boundary was the twenty-two-case prefix through REC-010.
The gate advanced it to the exact ordered twenty-three-case prefix, retained
the frozen first-twenty, twenty-one-, and twenty-two-request aggregate digests,
froze the actual twenty-three-request digest, and rechecked the existing size
ceiling. A millimetre/YZ REC-011 response realized through the unchanged
rectangle production route and oracle; REC-012 remained a typed inactive
failure before evaluation. No adapter schema or fingerprint changed.

`T12-REC-012` is the next additive activation. Before its gate passed, the
executor-owned adapter boundary was the twenty-three-case prefix through
REC-011. The gate advanced it to the exact ordered twenty-four-case prefix,
retained the frozen first-twenty, twenty-one-, twenty-two-, and twenty-three-
request aggregate digests, froze the actual twenty-four-request digest, and
rechecked the existing size ceiling. An exact public millimetre/XY REC-012
response realized through the unchanged rectangle production route and oracle.
Because REC-012 ends the rectangle catalog, CIR-001—not an invented REC-013—
remained a typed inactive failure before evaluation. No adapter schema or
fingerprint changed.

`T12-CIR-001` is the first schema-changing activation. Before its internal gate
passed, authority remained the twenty-four-case prefix. The completed
gate accepts candidate-response v2 with the benchmark-owned `circle` action,
rejects candidate-response v1 before evaluation, derives the exact ordered
twenty-five IDs from the executor, preserves request bytes/digests through
twenty-four, and freezes the actual twenty-five-request digest. A bounded CIR-
001 request and v2 response realize through the circle production route
and exact oracle; CIR-002 remained typed inactive at that gate. Request/evaluation/error v1,
fingerprint v1, the byte ceiling, and catalog/expectation versions do not move.

`T12-CIR-002` is a completed case-only authority transition. Before its internal
production and oracle evidence passed, this adapter was authoritative for the
exact twenty-five-case prefix through CIR-001. The gate derives an ordered
twenty-six-case prefix ending in CIR-002 from the executor, preserves the frozen
twenty-five-request aggregate, freezes the observed twenty-six-request
aggregate, and proves a bounded exact CIR-002 request and candidate-response-v2
evaluation through the unchanged circle route/oracle. CIR-003 remained typed
inactive at that gate. No envelope, fingerprint, byte-bound, error, benchmark catalog, or
candidate action schema changes in this transition.

`T12-CIR-003` is the completed first XZ circle transition and changes only the
executor-owned activated set. Before its internal production/oracle gate passed,
the adapter was authoritative for the ordered twenty-six-case prefix through
CIR-002. The completed case derives the twenty-seven-case prefix ending in
CIR-003, preserve the frozen twenty-six-request aggregate, freeze the observed
twenty-seven-request aggregate, and proved a bounded exact 25 mm XZ CIR-003
request and candidate-response-v2 evaluation through the unchanged circle
route/oracle. CIR-004 remained typed inactive at that gate. Envelope versions, the context
fingerprint, byte bound, error projection, and candidate action shape do not
change.

### CIR-004 through CIR-012 sequential authority

The remaining circle activations consume the exact geometry and adversarial
contracts in the benchmark-owned [circle case matrix](../RupaAgentCADBenchmark/DESIGN.md#cir-004-through-cir-012-case-matrix).
This adapter owns only their ordered external authority transition:

| Case | Activated count after gate | Required prior aggregate | Next inactive ID |
|---|---:|---|---|
| CIR-004 | 28 | CIR-003 / 27-request aggregate | CIR-005 |
| CIR-005 | 29 | CIR-004 / 28-request aggregate | CIR-006 |
| CIR-006 | 30 | CIR-005 / 29-request aggregate | CIR-007 |
| CIR-007 | 31 | CIR-006 / 30-request aggregate | CIR-008 |
| CIR-008 | 32 | CIR-007 / 31-request aggregate | CIR-009 |
| CIR-009 | 33 | CIR-008 / 32-request aggregate | CIR-010 |
| CIR-010 | 34 | CIR-009 / 33-request aggregate | CIR-011 |
| CIR-011 | 35 | CIR-010 / 34-request aggregate | CIR-012 |
| CIR-012 | 36 | CIR-011 / 35-request aggregate | ANG-001 |

Each row is a separate commit and remains inactive until its internal gate
passes. That commit derives the exact ordered IDs from the executor, reasserts
the prior digest, freezes the newly observed aggregate, proves bounded request
and candidate-response-v2 evaluation through the unchanged circle route/oracle,
and rejects the next ID before evaluation. CIR-012 uses the real next-category
ID ANG-001; no CIR-013 is invented. Envelope versions, context fingerprint,
byte bound, decision shape, error projection, and privacy boundary remain fixed.

### ANG-001 external authority

ANG-001 extends the exact ordered authority from 36 to 37 IDs while preserving
the frozen 36-request aggregate. The observed 37-request aggregate is
`b66ed71a2efccf115a81033c3bda0e9335c0a2a4c695ba5c58b49c9df7341b4e`.
The request reports the intersection capability as available because the
production route composes two exposed `createLineSketch` primitives.
One bounded v3 angle response traverses the same executor, production atomic
batch, and immutable source oracle; ANG-002 is rejected before evaluation.

### ANG-002 external authority

ANG-002 extends the exact ordered authority from 37 to 38 IDs while preserving
the frozen 37-request aggregate. The observed 38-request aggregate is
`6bd274e57fae5345c067f63a5191b60ccfbf35a76d794491b7a10df9a0c985d6`.
The request reports the same intersection capability as ANG-001
because the production route composes two exposed `createLineSketch`
primitives. One bounded v3 angle response traverses the same executor,
production atomic batch, and immutable source oracle; ANG-003 is rejected
before evaluation.

### ANG-003 external authority

ANG-003 extends the exact ordered authority from 38 to 39 IDs while preserving
the frozen 38-request aggregate. The observed 39-request aggregate is
`83f7c7b54c95ed2fc0304b98c455d3981dcd51380da7414f397de191333b5e6a`.
The request reports the same intersection capability as ANG-001 and ANG-002
because the production route composes two exposed `createLineSketch`
primitives. One bounded v3 angle response traverses the same production atomic
batch and immutable source oracle; ANG-004 is rejected before evaluation.

### ANG-004 external authority

ANG-004 extends the exact ordered authority from 39 to 40 IDs while preserving
the frozen 39-request aggregate. The observed 40-request aggregate is
`e2f928ac390783e8bcf5fdbb4e368156a188e3b49e81fee845d72602fd1d0649`.
The request reports the same intersection capability as the prior angle cases
because the production route composes two exposed `createLineSketch`
primitives. One bounded v3 angle response traverses the same production atomic
batch and immutable source oracle; ANG-005 is rejected before evaluation.

### ANG-005 external authority

ANG-005 extends the exact ordered authority from 40 to 41 IDs while preserving
the frozen 40-request aggregate. The observed 41-request aggregate is
`fb0228298f5bd1b38ddcafeeda2632236e487f2be8600e3abffed335f9f3df6d`.
It is measured from the exact bounded request bytes after the production route passes. The
request describes the XY intersection at (0, 0, 200) mm with a 75 mm +X first
segment and a 125 mm +Y second segment, producing an unsigned 90-degree angle.
One bounded v3 response traverses the same production atomic batch and
immutable source oracle; ANG-006 is rejected before evaluation. Envelope
versions, fingerprint, byte ceiling, and candidate action shape remain
unchanged.

### ANG-006 external authority

ANG-006 extends the exact ordered authority from 41 to 42 IDs while preserving
the frozen 41-request aggregate. The observed 42-request aggregate is
`a15fbc50a8f6476bd353b9508a10c88b6da03377aa173b413987e829642f16eb`,
measured from the exact bounded request bytes after the production route passes. The
request describes the XY intersection at (-50, 40, 250) mm with a 90 mm +X
first segment and a 150 mm second segment directed along
(-0.258819045103, 0.965925826289, 0), producing an unsigned 105-degree angle.
One bounded v3 response traverses the same production atomic batch and
immutable source oracle; ANG-007 is rejected before evaluation. Envelope
versions, fingerprint, byte ceiling, and candidate action shape remain
unchanged.

### ANG-007 external authority

ANG-007 extends the exact ordered authority from 42 to 43 IDs while preserving
the frozen 42-request aggregate
`a15fbc50a8f6476bd353b9508a10c88b6da03377aa173b413987e829642f16eb`.
The observed 43-request aggregate is
`b276bc61ebd50a39b603ba627890f6342121c2889f906b8349140f4bb932fbcd`, measured
from the exact bounded request bytes after the production route passes. The request describes the XY
intersection at (20, -35, 300) mm with a 105 mm +X first segment and a 200 mm
second segment directed along (-0.5, 0.866025403784, 0), producing an unsigned
120-degree angle. One bounded v3 response traverses the same production atomic
batch and immutable source oracle; ANG-008 is rejected before evaluation.
Envelope versions, fingerprint, byte ceiling, and candidate action shape remain
unchanged.

### ANG-008 external authority

ANG-008 extends the exact ordered authority from 43 to 44 IDs while preserving
the frozen 43-request aggregate
`b276bc61ebd50a39b603ba627890f6342121c2889f906b8349140f4bb932fbcd`.
The observed 44-request aggregate is
`47914bc2ecec829f01c24bfd62626a41e4a605a0a14c945bf6fc15913231d82c`, measured
from the exact bounded request bytes after the production route passes. The request describes the XY
intersection at (0, 0, 350) mm with a 120 mm +X first segment and a 250 mm
second segment directed along (-0.707106781187, 0.707106781187, 0), producing
an unsigned 135-degree angle. One bounded v3 response traverses the same
production atomic batch and immutable source oracle; ANG-009 is rejected before
evaluation. Envelope versions, fingerprint, byte ceiling, and candidate action
shape remain unchanged.

### ANG-009 external authority

ANG-009 extends the exact ordered authority from 44 to 45 IDs while preserving
the frozen 44-request aggregate
`47914bc2ecec829f01c24bfd62626a41e4a605a0a14c945bf6fc15913231d82c`.
The observed 45-request aggregate is
`6c9014e08de0670558528695d21790d489f0bc9516a6e1febefc6c3437b69c87`, measured
from the exact bounded request bytes after the production route passes. The
request describes the XY intersection at (75, 50, 400) mm with a 135 mm +X
first segment and a 300 mm second segment directed along
(-0.866025403784, 0.5, 0), producing an unsigned 150-degree angle. One bounded
v3 response traverses the same production atomic batch and immutable source
oracle; ANG-010 is rejected before evaluation. Envelope versions, fingerprint,
byte ceiling, and candidate action shape remain unchanged.

### ANG-010 external authority

ANG-010 extends the exact ordered authority from 45 to 46 IDs while preserving
the frozen 45-request aggregate
`6c9014e08de0670558528695d21790d489f0bc9516a6e1febefc6c3437b69c87`.
The observed 46-request aggregate is
`4f4f451db3ab64d9d5f5d657cb7b0ebe3c79a02d370ab2b56070b1d7e3396e65`, measured
from the exact bounded request bytes after the production route passes. The request describes the XY
intersection at (-75, -50, 450) mm with a 150 mm +X first segment and a 350 mm
second segment directed along (-0.965925826289, 0.258819045103, 0), producing
an unsigned 165-degree angle. One bounded v3 response traverses the same
production atomic batch and immutable source oracle; ANG-011 is rejected before
evaluation. Envelope versions, fingerprint, byte ceiling, and candidate action
shape remain unchanged.

### ANG-011 external authority

ANG-011 extends the exact ordered authority from 46 to 47 IDs while preserving
the frozen 46-request aggregate
`4f4f451db3ab64d9d5f5d657cb7b0ebe3c79a02d370ab2b56070b1d7e3396e65`.
The observed 47-request aggregate is
`08a9f3fa73e242fe7116dfb904e5d254fabe3a1cb61c2004021e239f42cde3de`, measured
from the exact bounded request bytes after the production route passes. The request describes the canonical
XZ plane with +Y normal and intersection (0, 0, 80) mm, with a 30 mm +X first
segment and a 60 mm second segment directed along
(0.707106781187, 0, 0.707106781187), producing an unsigned 45-degree angle.
One bounded v3 response traverses the same production atomic batch and
immutable source oracle; ANG-012 is rejected before evaluation. Envelope
versions, fingerprint, byte ceiling, and candidate action shape remain
unchanged.

### ANG-012 external authority

ANG-012 extends the exact ordered authority from 47 to 48 IDs while preserving
the frozen 47-request aggregate
`08a9f3fa73e242fe7116dfb904e5d254fabe3a1cb61c2004021e239f42cde3de`.
The observed 48-request aggregate is
`f7476b4da91164043c29215821395b37b98537441e1d3e99542973809eea9efd`, measured
from the exact bounded request bytes after the production route passes. The
request describes the canonical YZ plane with +X normal and intersection
(10, -20, 120) mm, with a 40 mm +Y
first segment and a 100 mm second segment directed along
(0, 0.5, 0.866025403784), producing an unsigned 60-degree angle. One bounded
v3 response traverses the same production atomic batch and immutable source
oracle; ANG-013 is rejected before evaluation. Envelope versions, fingerprint,
byte ceiling, and candidate action shape remain unchanged.

### ANG-013 external authority

ANG-013 extends the exact ordered authority from 48 to 49 IDs while preserving
the frozen 48-request aggregate
`f7476b4da91164043c29215821395b37b98537441e1d3e99542973809eea9efd`.
The observed 49-request aggregate is
`9164bb6b90dffb05f5c443b7918d273bb83de8ecbc90f4feebfbc31139193b3e`, measured
from the exact bounded request bytes after the production route passes. The
request describes the canonical
XZ plane with +Y normal and intersection (-15, 25, 180) mm, with a 50 mm +X
first segment and a 150 mm +Z second segment, producing an unsigned 90-degree
angle. One bounded v3 response traverses the same production atomic batch and
immutable source oracle; ANG-014 is rejected before evaluation. Envelope
versions, fingerprint, byte ceiling, and candidate action shape remain
unchanged.

### ANG-014 external authority

ANG-014 extends the exact ordered authority from 49 to 50 IDs while preserving
the frozen 49-request aggregate
`9164bb6b90dffb05f5c443b7918d273bb83de8ecbc90f4feebfbc31139193b3e`.
The observed 50-request aggregate is
`fde5e108d41d194197b4a2f0b88eb31b110ad3372d53bdddef51e29c8dc021ee`, measured from the exact
bounded request bytes after the production route passes. The request describes
the canonical YZ plane with +X normal and intersection (-25, 30, 275) mm, with
a 75 mm +Y first segment and a 225 mm second segment directed along
(0, -0.5, 0.866025403784), producing an unsigned 120-degree angle. One bounded
v3 response traverses the same production atomic batch and immutable source
oracle; ANG-015 is rejected before evaluation. Envelope versions, fingerprint,
byte ceiling, and candidate action shape remain unchanged.

### ANG-015 external authority

ANG-015 extends the exact ordered authority from 50 to 51 IDs while preserving
the frozen 50-request aggregate
`fde5e108d41d194197b4a2f0b88eb31b110ad3372d53bdddef51e29c8dc021ee`.
The observed 51-request aggregate is
`8a5baed7294693f150ce8e67494112f521b0667bfe1d4f6e45db0661e83d6f07`, measured from the exact
bounded request bytes after the production route passes. The request describes
the canonical XZ plane with +Y normal and intersection (40, -40, 325) mm, with
a 100 mm +X first segment and a 300 mm second segment directed along
(-0.707106781187, 0, 0.707106781187), producing an unsigned 135-degree angle.
One bounded v3 response traverses the same production atomic batch and immutable
source oracle; ANG-016 is rejected before evaluation. Envelope versions,
fingerprint, byte ceiling, and candidate action shape remain unchanged.

### ANG-016 external authority

ANG-016 extends the exact ordered authority from 51 to 52 IDs while preserving
the frozen 51-request aggregate
`8a5baed7294693f150ce8e67494112f521b0667bfe1d4f6e45db0661e83d6f07`.
The observed 52-request aggregate is
`53836e6352b776f1b2a0eccd81cc17d7046a489782a5ad678236d920e36f8a7a`, measured from the exact
bounded request bytes after the production route passes. The request describes
the canonical YZ plane with +X normal and intersection (60, 60, 425) mm, with
a 125 mm +Y first segment and a 375 mm second segment directed along
(0, -0.866025403784, 0.5), producing an unsigned 150-degree angle. One bounded
v3 response traverses the same production atomic batch and immutable source
oracle; BOX-001 is rejected before evaluation. Envelope versions, fingerprint,
byte ceiling, and candidate action shape remain unchanged.

### BOX-001 through BOX-012 sequential authority

BOX activation is a serial expansion from the current 52-ID prefix to 64 IDs.
BOX-001 first advances candidate-response v3 to v4 for the benchmark-owned
solid/box discriminators. The request envelope and public context do not carry
the candidate-response schema, so the exact 52-request aggregate
`53836e6352b776f1b2a0eccd81cc17d7046a489782a5ad678236d920e36f8a7a`
must remain byte-identical. Each BOX gate derives its ordered ID set only from
`DefaultCADActivatedCaseExecutor`, preserves the immediately preceding
aggregate literal, freezes the newly observed aggregate, and keeps the largest
request and response below one quarter of the 65,536-byte ceiling.

For each activated BOX case, bounded request generation preserves the public
lower-corner origin, dimensions, and unit. A v4 response traverses the same
benchmark executor, production `createExtrudedRectangle` controller route, and
exact source/B-Rep oracle. The case-specific valid mismatch remains an
`invalidSubmission` after exactly one publication and no retry; zero dimension,
wrong action kind, malformed or legacy schema, context mismatch, and inactive
case failures occur before evaluation or publication as owned by the
corresponding layer. The next lexical BOX ID remains inactive until its own
gate; after BOX-012, CYL-001 is the typed inactive boundary. BOX adds no direct
source, workspace, or oracle access to this adapter.

### BOX-002 external authority

BOX-002 preserves the frozen 53-request aggregate
`dd12c2cc346e37ec4f3dcecb396aa46bcfe69a82923a41041c36739b826d0b79` and
advances the observed 54-request aggregate to
`36bf68952c6a605df9e9bb4187929752ee42317f0a45506f9847bc265ac065ec`.
Its bounded v4 response describes a 25 × 25 × 25 mm translated cube with
lower-corner origin (20, -20, 0) mm and is evaluated through the production
extruded-rectangle/source/B-Rep route. A wrong lower-corner origin is rejected
after exactly one publication without retry, while zero width and BOX-003 are
typed prepublication/inactive failures. Request, evaluation, error, and
fingerprint contracts remain unchanged.

### BOX-003 external authority

BOX-003 preserves the frozen 54-request aggregate
`36bf68952c6a605df9e9bb4187929752ee42317f0a45506f9847bc265ac065ec` and
advances the observed 55-request aggregate to
`74353ca8a790b520689404973dbc370b59ec77f50ec81ac3a48c4387b94862c3`.
Its bounded v4 response describes a 50 × 30 × 20 mm rectangular solid with
lower-corner origin (-25, 15, 5) mm and is evaluated through the production
extruded-rectangle/source/B-Rep route. Swapping depth and height is rejected
after exactly one publication without retry, while zero depth and BOX-004 are
typed prepublication/inactive failures. Request, evaluation, error, and
fingerprint contracts remain unchanged.

### BOX-004 external authority

BOX-004 preserves the frozen 55-request aggregate
`74353ca8a790b520689404973dbc370b59ec77f50ec81ac3a48c4387b94862c3` and
advances the observed 56-request aggregate to
`dc4c6fa1f96ae4181f54d48b34ae77b95d2548bc90935a3c7f0d7c51743efd9a`.
Its bounded v4 response describes a 100 × 50 × 75 mm rectangular solid with
lower-corner origin (0, 0, -25) mm and is evaluated through the production
extruded-rectangle/source/B-Rep route. A valid box at z = 0 mm is rejected by
the immutable oracle after exactly one publication without retry, while zero
height and BOX-005 are typed prepublication/inactive failures. Request,
evaluation, error, and fingerprint contracts remain unchanged.

### BOX-005 external authority

BOX-005 preserves the frozen 56-request aggregate
`dc4c6fa1f96ae4181f54d48b34ae77b95d2548bc90935a3c7f0d7c51743efd9a` and
advances the observed 57-request aggregate to
`a7ae81207efbb6d315d2a11b61f7cbfa17d997e59ca74db7404c310bbecc24bb`.
Its bounded v4 response describes a 250 × 100 × 125 mm rectangular solid with
lower-corner origin (-125, -50, 0) mm and is evaluated through the production
extruded-rectangle/source/B-Rep route. A valid box with height 100 mm is
rejected by the immutable oracle after exactly one publication without retry,
while zero width is a typed prepublication failure; BOX-006 is the next
reviewed case. Request, evaluation, error, and fingerprint contracts remain
unchanged.

### BOX-006 external authority

BOX-006 preserves the frozen 57-request aggregate
`a7ae81207efbb6d315d2a11b61f7cbfa17d997e59ca74db7404c310bbecc24bb` and
advances the observed 58-request aggregate to
`1f0ecb07744e6525d6e68df789fb529ff3ad91220ff515603ea26a2f123d88d9`.
Its bounded v4 response describes a 0.1 × 0.05 × 0.025 m rectangular solid
with lower-corner origin (0, 0, 0) m and is evaluated through the production
extruded-rectangle/source/B-Rep route. Submitting the same numeric values in
centimetres is rejected by the immutable oracle after exactly one publication
without retry, while zero depth is a typed prepublication failure; BOX-007 is
the next reviewed case. Request, evaluation, error, and fingerprint contracts
remain unchanged.

### BOX-007 external authority

BOX-007 preserves the frozen 58-request aggregate
`1f0ecb07744e6525d6e68df789fb529ff3ad91220ff515603ea26a2f123d88d9` and
advances the observed 59-request aggregate to
`22a57a1631712e9cc4cac3a50c5d2886909e804d2e44338b15911637318b74be`.
Its bounded v4 response describes a 1 × 2 × 3 inch rectangular solid with
lower-corner origin (-1, -1, 0) inches and is evaluated through the production
extruded-rectangle/source/B-Rep route. Submitting the same numeric values in
millimetres is rejected by the immutable oracle after exactly one publication
without retry, while zero height is a typed prepublication failure; BOX-008 is
the next reviewed case. Request, evaluation, error, and fingerprint contracts
remain unchanged.

### BOX-008 external authority

BOX-008 preserves the frozen 59-request aggregate
`22a57a1631712e9cc4cac3a50c5d2886909e804d2e44338b15911637318b74be` and
advances the observed 60-request aggregate to
`6f7467cbe5f511521c5a1ba79811fb38fc60a9f77c8585a1950eff7ea9033f81`.
Its bounded v4 response describes a 300 × 300 × 300 mm translated cube with
lower-corner origin (100, 100, 100) mm and is evaluated through the production
extruded-rectangle/source/B-Rep route. A valid cube at x = 0 mm is rejected by
the immutable oracle after exactly one publication without retry, while zero
width is a typed prepublication failure; BOX-009 is the next reviewed case.
Request, evaluation, error, and fingerprint contracts remain unchanged.

### BOX-009 external authority

BOX-009 preserves the frozen 60-request aggregate
`6f7467cbe5f511521c5a1ba79811fb38fc60a9f77c8585a1950eff7ea9033f81` and
advances the observed 61-request aggregate to
`01837d577b9eaecc860279b474e8190c852777cf359910ced4196a1ca5c2e403`.
Its bounded v4 response describes a 12 × 12 × 12 mm cube with lower-corner
origin (-12, 0, 0) mm and is evaluated through the production
extruded-rectangle/source/B-Rep route. A valid cube with height 10 mm is
rejected by the immutable oracle after exactly one publication without retry,
while zero depth is a typed prepublication failure; BOX-010 is the next
reviewed case. Request, evaluation, error, and fingerprint contracts remain
unchanged.

### BOX-010 external authority

BOX-010 preserves the frozen 61-request aggregate
`01837d577b9eaecc860279b474e8190c852777cf359910ced4196a1ca5c2e403` and
advances the observed 62-request aggregate to
`7cce27a557abbfed9b6d8f1f020e14fff0b366497b79373071c7df625aa2078b`.
Its bounded v4 response describes a 400 × 200 × 50 mm rectangular solid with
lower-corner origin (0, -100, 50) mm and is evaluated through the production
extruded-rectangle/source/B-Rep route. Swapping width and depth to 200 × 400 mm
is rejected by the immutable oracle after exactly one publication without
retry, while zero height is a typed prepublication failure; BOX-011 is the next
reviewed case. Request, evaluation, error, and fingerprint contracts remain
unchanged.

### BOX-011 external authority

BOX-011 preserves the frozen 62-request
aggregate
`7cce27a557abbfed9b6d8f1f020e14fff0b366497b79373071c7df625aa2078b` and observes
the 63-request aggregate as
`404f138058b2e8826a582a2f957ffc6fae0174ef4a11b6f0820dccb14378917a`.
Its bounded v4 response describes a
0.5 × 0.5 × 0.5 m cube with lower-corner origin (-0.25, -0.25, 0) m and is
evaluated through the production extruded-rectangle/source/B-Rep route.
Submitting the same numeric values and origin in centimetres is rejected by the
immutable oracle after exactly one publication without retry, while zero width
is a typed prepublication failure. Request,
evaluation, error, and fingerprint contracts remain unchanged.

### BOX-012 external authority

BOX-012 is the BOX-category completion boundary. It preserves the frozen 63-request
aggregate
`404f138058b2e8826a582a2f957ffc6fae0174ef4a11b6f0820dccb14378917a` and observes
the 64-request aggregate as
`e7f1f8084f0c61855d28fe7e7e28a0860eba3ab6993ae5b9859d28448948618c`.
Its bounded v4 response describes a
75 × 125 × 175 mm rectangular solid with lower-corner origin (25, 25, -75) mm
and is evaluated through the production extruded-rectangle/source/B-Rep route.
Submitting the same dimensions at z = -50 mm is rejected by the immutable oracle
after exactly one publication without retry, while zero depth is a typed
prepublication failure. This is the verified 64-ID BOX-category completion
boundary. Request, evaluation, error, and fingerprint contracts remain
unchanged.

### CYL-001 external authority contract

CYL-001 advances external authority from the verified 64-ID BOX boundary to
exactly 65 IDs only after the benchmark's production/oracle gate succeeds. It
preserves the exact 64-request aggregate
`e7f1f8084f0c61855d28fe7e7e28a0860eba3ab6993ae5b9859d28448948618c`;
the observed 65-request aggregate is
`ad9d6ca086b3be46bcd2d778eb22beaa3b506a4f84216e0195f11aafbbef19e0`.
CYL-002 remains typed inactive.

The bounded candidate response adds `CADSolidAction` kind `cylinder` with
`name`, `baseCenter`, `axis`, `radius`, and `depth`, so candidate-response
advances from v4 to v5. The envelope guard rejects v1 through v4 before
decision decoding. Request, evaluation, error, fingerprint, catalog,
expectation, capability, tolerance, and the 65,536-byte ceiling remain
unchanged. A correct CYL-001 v5 response traverses the same benchmark executor,
production `createExtrudedCircle` controller route, and exact source/B-Rep
oracle. Radius 6 mm returns the sanitized `invalidSubmission` result after one
publication and no retry; degenerate dimensions/axis or a box substitute fail
before publication. No private expectation, FeatureID, source/topology detail,
diagnostic, telemetry, or workspace state enters any JSON envelope.

### CYL-002 external authority contract

CYL-002 reuses candidate-response v5 and the existing `solid/cylinder` wire
shape. Its bounded response preserves base centre (25, -25, 0) mm, +X axis,
radius 10 mm, and depth 50 mm and traverses the unchanged executor, production
`createExtrudedCircle` route, and immutable source/B-Rep oracle. An otherwise
exact +Z-axis response becomes sanitized `invalidSubmission` after one
publication without retry; a zero axis fails before command/publication. The
frozen 65-request aggregate
`ad9d6ca086b3be46bcd2d778eb22beaa3b506a4f84216e0195f11aafbbef19e0`
must remain unchanged before the observed 66-request aggregate is frozen.
The 66-request aggregate is
`53b35fd441b1bbb210c20c55e4913e5bcea19213dba1b684ab1cf9b916797702`.
CYL-003 remains typed inactive. Envelopes, fingerprint, byte bound, catalog,
tolerance, privacy, and error projection do not change.

### CYL-003 external authority contract

CYL-003 reuses candidate-response v5 and the existing `solid/cylinder` wire
shape. Its bounded response preserves base centre (-50, 20, 10) mm, +Y axis,
radius 25 mm, and depth 100 mm and traverses the unchanged executor, production
`createExtrudedCircle` route, and immutable source/B-Rep oracle. An otherwise
exact +Z-axis response becomes sanitized `invalidSubmission` after one
publication without retry; a zero axis fails before command/publication. The
frozen 66-request aggregate
`53b35fd441b1bbb210c20c55e4913e5bcea19213dba1b684ab1cf9b916797702`
must remain unchanged before the observed 67-request aggregate
`c6d27d83af09579d4d4526dbd3f27c212af7ccaa1d17b878c60dd3ae9f7991e8`
is frozen.
CYL-004 remains typed inactive. Envelopes, fingerprint, byte bound, catalog,
tolerance, privacy, and error projection do not change.

## Runtime Flows

```mermaid
sequenceDiagram
    participant CLI as Dedicated CLI
    participant J as JSON adapter
    participant X as Activated executor
    participant C as JSON candidate
    CLI->>X: context(caseID)
    X-->>CLI: live-equivalent public context
    CLI->>J: request envelope + fingerprint
    J-->>CLI: bounded canonical JSON
    Note over CLI: external Agent returns response JSON
    CLI->>J: evaluate(responseData)
    J->>J: fixed bounded decode + schema/case/fingerprint-shape validation
    J->>X: evaluate(caseID, internal C)
    X->>C: exact live public context
    C->>C: recompute and compare fingerprint
    C-->>X: existing typed decision
    X-->>J: sanitized result after production route + oracle
    J-->>CLI: evaluation envelope
```

## State, Ownership, and Lifecycle

Envelope, fingerprint, decision, result, and error values are immutable and
`Sendable`. The JSON candidate owns one immutable validated response for one
evaluation call. Input buffers live only through bounded decode; no file
handle, controller, workspace, oracle snapshot, or private expectation is
retained. The benchmark executor remains the owner of fresh project lifecycle
and cleanup.

## Failure, Concurrency, and Constraints

One CLI evaluation executes one case at serial concurrency 1. The adapter adds
no retry, scheduler, shared cache, or mutable global state. A decode or binding
failure occurs before candidate action dispatch. A non-realized benchmark
outcome remains a result rather than being changed to adapter success. After a
published mutation the benchmark's no-retry result is preserved. Cancellation,
deadline, oracle failure, and cleanup failure retain their benchmark
classification and are projected only to stable non-private codes.

## Verification and Change Impact

| Invariant | Behavioral evidence |
|---|---|
| Explicit vendor-neutral wire shape | Golden request/response/evaluation JSON includes the BOX-001...012 `solid/box` decisions and CYL-001...003 `solid/cylinder`; candidate-response v5 carries the explicit discriminators, v1 through v4 and unknown current-schema discriminators are rejected, and every direct and nested case ID is the same scalar string. |
| Exact public-context binding | The request fingerprint equals the live executor context; changed schema, case, context byte, capability, budget, or fingerprint is rejected before publication. |
| Current activation boundary | The executor-derived ordered set is exactly LIN-001...012, REC-001...012, CIR-001...012, ANG-001...016, BOX-001...012, and CYL-001...003. The 66-request prefix remains `53b35fd441b1bbb210c20c55e4913e5bcea19213dba1b684ab1cf9b916797702`; the observed 67-request aggregate is `c6d27d83af09579d4d4526dbd3f27c212af7ccaa1d17b878c60dd3ae9f7991e8`; all three cylinders traverse production `createExtrudedCircle` and the exact source/B-Rep oracle, while CYL-004 remains typed inactive. |
| Bounded I/O | Exact-limit input succeeds, `limit + 1` fails before decode and leaves executor evaluation count zero, chunked stdin and file paths behave identically, no public typed-response execution bypass exists, encoded output cannot exceed the same bound, and the guaranteed infrastructure document is byte-equal to normal encoding, bounded, and decodable. |
| Candidate/oracle separation | Static dependency and source scans prove the adapter imports only public benchmark contracts; encoded fixtures contain no expectation/oracle/source snapshot fields or values. |
| Same production route | JSON candidates for activated line, rectangle, circle, angle, box, and cylinder cases realize through the public executor; wrong geometry publishes once then the category's exact oracle rejects without retry. |
| Non-action honesty | Valid `unsupported` and `finish` responses reach the benchmark candidate boundary, produce typed prepublication `invalidSubmission`, zero publication, and no fallback reference action. |

Changes to public candidate Codable shapes, public context fields, capability
snapshot generation, activation boundary, fingerprint algorithm, byte bound,
executor result projection, or CLI exit mapping require rechecking this design,
the benchmark design, the CLI design, golden JSON, and process-level tests. A
case-ID Codable change also requires the benchmark-owned manifest/catalog and
expectation version/digest transition before adapter fingerprints are refrozen.
