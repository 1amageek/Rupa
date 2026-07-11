# Modeling Performance Benchmark

The benchmark reports three Rupa execution boundaries and one Blender mesh
baseline:

| Layer | Workload |
|---|---|
| Kernel | Validated CAD source to exact BRep and meshes. Edit includes graph-stable local source validation. |
| Core | Kernel work plus document generation, evaluation cache, and undo history. |
| Agent | Core work plus isolated transaction and command response. Existing names `create_bodies` and `edit_one_body` remain the external latency gate. |
| Blender | Direct mesh datablock/object creation or direct mesh vertex edit followed by visible update. |

Process startup, input-program construction, and initial edit fixture construction
are outside the timed region. The Agent-vs-Blender gate compares visible outcomes,
not equivalent geometry semantics: Rupa retains exact parametric/BRep source while
the Blender baseline retains mesh source. Kernel/Core/Agent breakdowns prevent
that semantic difference from being mistaken for protocol overhead.

The equivalence gate requires both median and p95 latency for both shared
workloads to be at most `2.0x` Blender. It measures decoded Agent command
execution. Rupa's Agent request encoding is reported separately and is not
compared with Blender's in-process Python API, which also excludes script
generation and parsing.

The comparison tool requires at least 100 iterations by default. It recomputes
all reported statistics from the samples and verifies that Agent creation and
editing each perform one evaluation and one history mutation. The edit workload
must rebuild and tessellate exactly one feature/body without replay fallback.
Use `--minimum-iterations 1` only for a local smoke run, never for equivalence
certification.

```bash
cd /Users/1amageek/Desktop/3D/RupaKit
swift run -c release rupa-performance-benchmark --body-count 100 --iterations 200 --warmups 20 > /tmp/rupa-modeling.json

/Applications/Blender.app/Contents/MacOS/Blender --factory-startup --background \
  --python /Users/1amageek/Desktop/3D/Rupa/Benchmarks/blender_modeling_benchmark.py -- \
  --body-count 100 --iterations 200 --warmups 20 > /tmp/blender-modeling.log

python3 /Users/1amageek/Desktop/3D/Rupa/Benchmarks/compare_modeling_benchmarks.py \
  /tmp/rupa-modeling.json /tmp/blender-modeling.log
```
