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

## CLI exit codes observed against this build

| Run | Observed exit code |
|---|---|
| `--rupakit-path /private/tmp` (not a repository) | `1`, with the typed error and no report |
| The recorded standard-fixture run (three rows reject) | `2` |
| `--bodies 1 --segments 8 --iterations 10` (no row rejects, three not measured) | `3` |
