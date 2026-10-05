# NativeLineRasterizer

## Purpose and Scope
A RupaRendering child owning the original native line raster geometry shared by native display and optical transport.

## Responsibilities and Boundaries
The caller retains the original LowLevelMesh and material/occurrence authority. This child retains the raster mesh, consumes actual camera projection and backing scale, and replaces the same ModelEntity mesh used for drawing. It does not approximate optical-only geometry or own frame publication. Caller stages every member, validates every pending member, then commits all members without suspension.

## Related Designs
| Design | Relationship | Contract Used | Summary | Cautions |
|---|---|---|---|---|
| [RupaRendering](../DESIGN.md) | parent | current frame admission | Caller charges remaining aggregate limits | No private limit reset |
| [RealityViewport](../RealityViewport/DESIGN.md) | used by | native current camera | Actual world placement and projection | Publication follows complete update |

## Architecture
```text
original native line mesh + world occurrence + camera + pixel scale
    -> near/far clipping -> actual one-pixel ribbon triangles
        -> same retained native mesh -> native display + optical transport
```

## Contracts and Invariants
All original triangle parts and material indices are preserved. Original line endpoints are clipped in camera depth, expanded to one backing pixel in the actual native projection, and transformed back to the occurrence's local space. Degenerate projected lines draw a one-pixel square in both consumers. Position, triangle and byte capacities are admitted before native allocation. Source part/line maxima are checked each update. Scoped synchronous native buffers never escape. Every addressable destination element is initialized before use.

## State, Ownership, and Lifecycle
MainActor owns original and two raster meshes/resources plus retained bounded part scratch. Updates write only the inactive raster buffer; a failed stage leaves the active native draw buffer intact. Pending entity/world-transform authority is checked before commit. Both native buffer capacities and all three part-storage capacities are admitted before allocation. A caller owns one service per occurrence and destroys it when that occurrence is removed. No background tasks or independent frame authority exist.

## Failure, Concurrency, and Constraints
Invalid source stride/index/topology, noninvertible placement, absent finite camera projection or backing scale, cancellation, and exceeded caller limits throw. Partial updates are never a complete-frame receipt. Caller retains the preceding frame until every update succeeds; commit-all follows validate-all in the same actor without suspension. Immutable snapshot capture can explicitly consume the prepared inactive mesh before native publication.

## Verification and Change Impact
Deferred source-phase verification must cover perspective/orthographic, near/far crossings, degenerate lines, body/preview wires, material parts, nonuniform affine placement, byte/vertex/triangle exhaustion, cancellation, actual GPU draw and shared optical triangles. Projection changes affect spatial labels and pointer placement as well as raster geometry.

A stage may receive plannedLocalTransform without mutating the mounted entity. It retains original world/parent/mesh authority and computes triangles using the planned parent-composed world matrix. Validation checks original transform, parent, mesh identity and material count; complete appearance equality is the caller’s original source-frame contract because native Material existentials provide no value equality. Commit publishes both planned transform and inactive mesh after validate-all, without suspension.

Camera checkpoint composition retains the actual published draw lane identity and
its full initialized byte/part snapshot before synchronous updates. On rollback,
`restorePublishedMesh` selects only that original owned lane and discards staged
publication. Caller restoration includes its original ModelComponent and bytes;
restoring a lane flag alone is insufficient if multiple updates reused its buffer.
