# Meta Analysis

## Central Findings

1. The largest gap is not a longer command list. Rupa lacks the shared mutable
   mesh, attribute, modifier, procedural graph, asset, and plugin foundations
   from which Blender's breadth is composed.
2. Rupa's exact CAD and typed Agent architecture is materially stronger than a
   Blender comparison suggests in parametric ownership, deterministic mutation,
   and topology-aware diagnostics. That strength only applies to implemented
   operation families.
3. Adding sculpt, rigging, rendering, or simulation directly to Swift-CAD would
   violate the current dependency design. They require optional higher modules
   over universal scene, artifact, and capability contracts.
4. Agent modeling parity requires a compact procedural program representation,
   not only faster execution of large explicit command payloads.

## Structural Gaps

| Foundation gap | Downstream capability families blocked |
|---|---|
| Editable polygon mesh and attributes | General mesh editing, sculpt, UV, weights, retopology, Geometry Nodes |
| Generic operation/modifier graph | Non-destructive modeling, procedural tools, simulation modifiers |
| Asset/reference/plugin system | Reusable materials, node groups, rigs, brushes, multi-file projects, third-party tools |
| GPU scene shading | Material inspection, sculpt feedback, lighting, animation preview, rendering |
| Animation property graph | Rigging, shape keys, physics timelines, camera animation, video integration |
| Artifact/solver execution | Physics bake, engineering simulation, render jobs, external analyses |

## Limitation

The inventory is exhaustive at operation-family level. Individual properties,
node variants, brush presets, and manual introduction pages are represented by
their owning runtime because Rupa lacks that runtime as a whole.
