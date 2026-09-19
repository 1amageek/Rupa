# Viewport Shading Panel

## Purpose and Scope

Child of [RupaUI](../DESIGN.md), with no children. Presents native, compact
controls for the existing viewport shading contract.

## Responsibilities and Boundaries

Owns control layout and value bindings, not shading state, rendering, material
editing, geometry, persistence, camera, or undo. MainView owns popover visibility.

## Related Designs

| Design | Relationship | Contract Used | Summary | Cautions |
|---|---|---|---|---|
| [RupaUI](../DESIGN.md) | parent | Session binding and error presentation | MainView forwards one setting value to Rendering. | Failed edits retain the prior value. |
| [Rendering](../../RupaRendering/DESIGN.md) | depends on | `ViewportShading`, `ViewportControlSession.setShading` | Owns validation, lifetime, and effective display-mode behavior. | Controls cannot claim an unsupported rendering effect. |

## Architecture

```text
Native controls -> MainView binding -> ViewportControlSession -> Viewport renderer
```

## Contracts and Invariants

- Lighting and solid color apply to Solid and Solid + Mesh Edges. Studio-only
  rotation and specular controls are inactive for MatCap and Flat.
- Light rotation uses a continuous native slider. Numeric precision does not
  create hundreds of discrete tick marks. The label and current angle occupy
  a separate row so the track retains the panel's available width.
- Wire color applies to Wireframe and Solid + Mesh Edges. Background applies
  to all modes. Culling applies only to Solid and Normals; line-pass modes show
  the limitation next to the inactive control.
- Flat means unlit base color. MatCap uses Rendering's built-in texture, not a
  UI-generated preview. Existing material base colors are read-only inputs.
- Native color pickers emit opaque, finite color values. Every edit updates
  only the selected field of the current value, preserving other settings.
- New document lifetimes receive Rendering defaults; closing the popover does
  not reset settings. No source transaction, save, or history entry is created.

## State, Ownership, and Lifecycle

The injected binding reads the document-lifetime MainActor session. The panel
retains no alternate source of truth. Native focus and popover state end with
their view lifetime.

## Failure, Concurrency, and Constraints

MainView reports Rendering's typed validation/mount failures. Controls use
native accessibility labels and bounded layout; they never prepare geometry.

## Verification and Change Impact

[UI tests](../../../Tests/RupaUIPackageTests/WorkspaceViewportControlPresentationTests.swift)
exercise binding forwarding and mode applicability. Rendering contract/GPU
tests prove actual effects; signed-App checks prove popover discoverability
and interaction. Changes to the rendering contract require rechecking both.
