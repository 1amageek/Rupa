# Agent Involute Spur Gear Artifact

This directory contains a complex CAD artifact created through Rupa's public
headless CLI automation boundary.

## Geometry

| Parameter | Value |
|---|---:|
| Gear type | External involute spur gear |
| Tooth count | 24 |
| Module | 2 mm |
| Pressure angle | 20 degrees |
| Pitch diameter | 48 mm |
| Outside diameter | 52 mm |
| Root diameter | 43 mm |
| Face width | 12 mm |
| Bore diameter | 8 mm |

Each tooth contains two three-segment cubic Bezier approximations of the
involute flanks, an exact circular addendum arc, two radial root transitions,
and an exact circular dedendum arc. The sampled maximum deviation between the
analytic involute and the Bezier approximation is 0.000165565 mm. The bore is
an inner loop in the same source sketch, not a visual-only cutout.

## Execution Evidence

```text
create-gear-sketch.json
    -> rupa command apply
        -> 145-entity source sketch
            -> rupa model extrude
                -> one CAD body
                    -> document validation
                    -> B-Rep topology evaluation
                    -> viewer mesh evaluation
```

Rupa reported one source sketch, 145 source entities, one material region, one
generated body, 246 generated faces, and a viewer mesh with 32,434 vertices and
38,998 triangles. The evaluated bounds are 52 mm by 52 mm by 12 mm.

The isometric PNG is projected from the same parametric outline used by the CAD
source. It is not a screenshot from the Rupa viewport. STEP and STL exports were
cancelled after exceeding a five-minute resource bound; the native CAD package,
B-Rep evaluation, and viewer mesh evaluation completed successfully.

## Files

| File | Purpose |
|---|---|
| `agent-involute-spur-gear.swcad` | Native editable Rupa CAD artifact |
| `create-gear-sketch.json` | Exact AutomationCommand payload |
| `gear-specification.json` | Dimensional and approximation contract |
| `verification-report.json` | Executed source, solid, and mesh evidence |
| `gear-profile.svg` | Parametric 2D profile preview |
| `gear-isometric-preview.png` | Isometric presentation preview |
| `generate_gear_artifacts.py` | Deterministic command/specification/preview generator |

## Manufacturing Boundary

This is a validated CAD demonstration artifact, not a certified manufacturing
drawing. The root transition is radial rather than a cutter-generated trochoid.
Backlash, profile shift, crowning, helix, material, heat treatment, surface
finish, and tolerance class remain unspecified.
