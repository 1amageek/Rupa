# Spatial Camera State

## Purpose and Scope
Child of [RealityViewport](../DESIGN.md), with no children. Owns an immutable
checkpoint of actual mounted spatial decorations across one synchronous camera
publication. It does not own the requested camera, projection or viewport readiness.

## Responsibilities and Boundaries
SpatialResources supplies its original entities, mutable native meshes and logical
collision/grid state. The checkpoint owns exact previous native bytes/parts and
entity state. NativeLineRasterizer owns its published lane identity. The viewport
may retain base/delta checkpoints across sibling updates and restores them on a
later source failure while retaining its own requested-camera retry policy.

## Related Designs
| Design | Relationship | Contract Used | Summary | Cautions |
|---|---|---|---|---|
| [RealityViewport](../DESIGN.md) | parent | mounted spatial/source readiness | Coordinates complete publication | Token does not restore camera authority |
| [SpatialStorageAdmission](../SpatialStorageAdmission/DESIGN.md) | depends on | original shared preparation/lease | Reserves all snapshot storage first | No private allowance or release gap |
| [NativeLineRasterizer](../../NativeLineRasterizer/DESIGN.md) | coordinates with | original published lane restoration | Keeps actual draw and optical mesh coherent | Original active bytes must survive multiple updates |

## Architecture
```text
original mounted decorations -> measure exact app snapshot storage
 -> same-pool reservation -> immutable entity/source-buffer/lane checkpoint
 -> synchronous source updates -> complete success releases checkpoint
                          -> failure restores original bytes/state/lane
```

## Contracts and Invariants
Capture uses the actual initialized native vertex/index buffer byte counts and part metadata.
All application copies are admitted before materialization. Native borrows are
synchronous and no pointer escapes. Restoration first validates unchanged buffer
capacity, then restores exact original bytes/parts and original entity parent,
transform, enabled and model state without suspension. Original active ribbon
buffers are included so a second update cannot overwrite checkpoint authority.
Collision/grid membership and source metadata restore under the same owner.
New retained raster buffers remain counted even if their publication is cancelled.
Externally held tokens suppress duplicate local snapshots; the holding caller
must restore all affected children on failed sibling publication. The outer owner/sectioned mounting roots are identity anchors, not restoration
records: their readiness visibility/parent/transform belong to the viewport and
must not be re-enabled by child rollback. Tokens never
cross actor isolation and may not span an await/source replacement.

## State, Ownership, and Lifecycle
The token retains original entities/meshes and an ARC same-pool storage lease.
Capture/restore/release are MainActor operations. Its isolated release decrements
the owner's temporary snapshot accounting and releases the lease exactly once.
Root source byte reporting excludes lease-backed checkpoint bytes; standalone
snapshot bytes remain part of the actual owner contribution.

## Failure, Concurrency, and Constraints
Source mismatch, native capacity changes, checked-size overflow, cancellation and
remaining-byte exhaustion are explicit failures before mutation. Pending glyphs
restore decoration state but preserve the async glyph request and failure/key
lifecycle. No old camera state is relabeled as the requested current camera.

## Verification and Change Impact
After complete source implementation, exercise pending glyphs after changed axes,
failed camera-line conversion, base success/delta failure, post-ribbon sibling
failure, repeated updates before rollback, capacity refusal and release. Use the
actual Native scene and GPU capture; source-only snapshots prove no runtime claim.
