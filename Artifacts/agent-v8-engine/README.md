# Agent V8 Engine CAD Artifact

This directory contains a mechanically constrained V8 cutaway assembly created
through Rupa's public headless CLI automation boundary. It is an original
4.0-liter-class design, not a dimensional copy of a production engine.

## Design Contract

| Parameter | Value |
|---|---:|
| Architecture | 90-degree cross-plane V8 |
| Bore | 86 mm |
| Stroke | 86 mm |
| Calculated displacement | 3,996.458 cc |
| Connecting rod center distance | 150 mm |
| Cylinder pitch | 94 mm |
| Crankshaft support | 5 main journals |
| Static crank angle | 30 degrees |
| Generated CAD bodies | 61 |

The four throw phases are `30`, `120`, `300`, and `210` degrees. Throws one
and four are opposed, throws two and three are opposed, and the two throw
planes are orthogonal. This matches the defining cross-plane relation described
for a conventional V8 crankshaft in
[JPH0262443A](https://patents.google.com/patent/JPH0262443A/en). The arrangement
also uses the four crankpins and five journals documented for a 90-degree V8 in
[US4833940A](https://patents.google.com/patent/US4833940A/en).

Every piston pin is solved from exact slider-crank closure rather than placed
by eye. For bank-axis unit vector `a`, crankpin position `q`, and rod length
`L`, the outward solution is:

```text
s = dot(a, q) + sqrt(L^2 - |q - dot(a, q)a|^2)
pistonPin = s a
```

This is the vector form of the crank-and-connecting-rod position relation shown
in [MIT OpenCourseWare 2.141](https://ocw.mit.edu/courses/2-141-modeling-and-simulation-of-dynamic-systems-fall-2006/dfb7d1ed209da291ee93b7ec5bf41608_modulated_transf.pdf).
The measured rod-length residual is zero at the precision recorded in the
generated kinematics report.

## Assembly Structure

```text
90-degree cylinder banks
    -> 8 pistons + 8 wrist pins
        -> 8 fixed-length connecting rods
            -> 4 phased crankpins
                -> 8 crank webs + 8 counterweights
                    -> 5 main journals + timing wheel + flywheel
```

The near-side cylinder deck and valve cover are intentionally removed. This is
a cutaway decision that exposes all eight piston/rod paths; it is not missing
source data accidentally treated as a complete exterior.

## Execution Evidence

```text
generate_v8_artifacts.py
    -> create-v8-engine-batch.json
        -> rupa new
        -> rupa batch --mode file --in-place
            -> one atomic history entry
            -> 61 source mutations / 122 source features
            -> agent-v8-engine.swcad
                -> rupa validate
                -> rupa mesh --mode file
```

The atomic batch completed with one evaluation pass and no error diagnostics.
An independent reload validated the saved source. A separate viewer evaluation
generated 61 body meshes, 1,433,418 vertices, and 1,432,800 triangles inside
457.000 by 389.348 by 307.668 mm bounds. The dense circular tessellation is
runtime evidence, not a target mesh budget.

## Files

| File | Purpose |
|---|---|
| `agent-v8-engine.swcad` | Native editable Rupa CAD package |
| `create-v8-engine-batch.json` | Exact public AutomationBatch request |
| `v8-engine-specification.json` | Dimensions and all 61 source primitives |
| `v8-kinematics-report.json` | Per-cylinder closure and crank-phase evidence |
| `verification-report.json` | Executed batch, reload, and mesh evidence |
| `v8-isometric-preview.png` | Presentation view from the same primitive list |
| `generate_v8_artifacts.py` | Deterministic request/specification/preview generator |

## Engineering Boundary

This artifact proves that an external Agent can generate a nontrivial,
mechanically constrained multi-body CAD assembly through the Rupa CLI. It is
not a production-ready combustion engine. The following remain deliberately
unspecified: combustion chambers, piston rings, valve train, cam drive,
bearings, fasteners, lubrication and cooling galleries, intake/exhaust flow,
materials, fits, tolerances, fatigue, thermal analysis, combustion analysis,
manufacturing process, and regulatory validation.

The connecting rods and crank webs use circular demonstration sections so the
kinematic structure remains visible. They must be replaced by stress-designed
forgings before manufacturing use.
