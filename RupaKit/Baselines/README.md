# Recorded baselines

`responsiveness-baseline.json` is the recorded responsiveness baseline the
`RupaRendering` performance acceptance table is compared against. It is produced
by `rupa-responsiveness-baseline`, whose contract is owned by
[RupaResponsivenessBaselineCLI](../Sources/RupaResponsivenessBaselineCLI/DESIGN.md).

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
