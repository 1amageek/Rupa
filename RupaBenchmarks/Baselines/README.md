# Recorded baselines

`responsiveness-baseline.json` is a recorded responsiveness measurement of the
plan preparation path. It is produced by `rupa-responsiveness-baseline`, whose
contract is owned by
[RupaResponsivenessBaselineCLI](../Sources/RupaResponsivenessBaselineCLI/DESIGN.md).

Both files in this directory are historical records, not current evidence. Read
the next section before citing either of them.

## What these recordings no longer evidence

The viewport now draws through a mounted RealityKit frame. Every drawing figure
in this directory was taken from a renderer the application no longer runs, so
no drawing figure here describes the shipped path.

| Recording | Still evidence for | No longer evidence for |
|---|---|---|
| `responsiveness-baseline.json` | Nothing on its own: it also predates the report shape the runner now emits, and its `pathCount`, `strokeCount` and `projectedPointCount` come from a SwiftUI Canvas renderer that was already gone when it was last read. | Any drawing, frame or presentation figure. Its `canvasConsumption` row is a legacy encoder's timing. |
| `signed-app-responsiveness-2026-09-05.md` | The footprint series and the observation and interaction findings, which do not depend on the encoder. | Its `Surface command encoding` series, which measured the retired Metal surface encoder. |

A current plan-preparation recording requires a fresh Release run from a clean
working tree, because a run taken from a dirty tree records a `-dirty` revision
that does not identify the measured sources. Until such a run exists, the plan
preparation rows have no recorded evidence in this repository, and the
signed-application run owns every frame, drawing and observation gate.

Reproduce it with a Release build:

```
swift build -c release --product rupa-responsiveness-baseline
.build/release/rupa-responsiveness-baseline \
  --output Baselines/responsiveness-baseline.json \
  --rupakit-path <RupaKit> --swift-cad-path <swift-CAD>
```

The report names the fixture digest, the acceptance-table inputs with the rule
that selected them, and both repository revisions. Two reports are comparable
only when the digest, the fixture version, the iteration counts, the build
configuration, and both revisions match. A revision carrying a `-dirty` suffix
was measured from a working tree with uncommitted changes under that package
path, so it does not identify the measured sources exactly.

The report does not record the toolchain, so the toolchain is part of the
comparability rule and is stated here instead. The recorded run was built and
run with `TOOLCHAINS=org.swift.64202608141a`, Apple Swift version 6.4-dev
(LLVM a157c5eb1c32510, Swift 424cae54c1a10da), targeting
`arm64-apple-macosx27.0.0`. Two reports produced by different toolchains are not
comparable.

The build configuration is part of the same comparability rule, and for a reason
the digest alone does not show. The fixture digest covers materialized vertex
positions, so it covers the results of the lateral `cos` and `sin` evaluations,
which this toolchain evaluates differently under `-Onone` and `-O`. An isolated
reproduction of the lateral loop at the standard segment count showed ten of
6284 sampled values differing by one unit in the last place, which changes the
digest. The recorded run is a Release build; a Debug build of the same sources
reports a different digest for the same fixture parameters, so any document or
report cited as the same content must also come from a Release build.

## CLI exit codes observed against this build

| Run | Observed exit code |
|---|---|
| `--rupakit-path /private/tmp` (not a repository) | `1`, with the typed error and no report |
| The recorded standard-fixture run (three rows reject) | `2` |
| `--bodies 1 --segments 8 --iterations 10` (no row rejects, three not measured) | `3` |

These codes were observed against the build that still measured drawing. The
drawing row is now permanently not measured, so `0` is unreachable and `3` is
the best outcome a clean run can produce, as
[RupaResponsivenessBaselineCLI](../Sources/RupaResponsivenessBaselineCLI/DESIGN.md)
states.
