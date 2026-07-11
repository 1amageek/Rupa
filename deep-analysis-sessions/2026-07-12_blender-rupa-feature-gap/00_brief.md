# Brief

| Field | Value |
|---|---|
| session_id | `session:blender-rupa-feature-gap` |
| created | 2026-07-12T00:00:00+09:00 |
| task_type | Capability gap analysis |
| domain | CAD and DCC product architecture |
| expected_output | Exhaustive operation-family inventory of Blender capabilities absent or incomplete in Rupa |
| constraints | Use Blender primary documentation, verify Rupa against implementation paths, distinguish partial from missing, and preserve module responsibility boundaries |

## User Request

Identify every capability that Blender has and Rupa lacks.

## Open Questions

- Whether compositing, motion tracking, and video editing are eventual Rupa product requirements or comparison-only gaps.
- Whether Blender-compatible Python is a target or whether a typed Swift/plugin/Agent contract should provide equivalent extensibility.
