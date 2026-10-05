# Camera Publication

## Purpose and Scope
Child of [RealityViewport](../DESIGN.md), without children. Owns the original body
wire publication checkpoint across one synchronous camera update.

## Responsibilities and Boundaries
The viewport retains requested camera authority and coordinates base/delta spatial
checkpoints. This child retains previous body wire model state, original active
raster lane and exact initialized native bytes. It does not restore an old camera
or publish an old frame as successful under new inputs.

## Related Designs
| Design | Relationship | Contract Used | Summary | Cautions |
|---|---|---|---|---|
| [RealityViewport](../DESIGN.md) | parent | complete synchronous camera publication | Coordinates all siblings | Token never spans suspension |
| [Spatial Camera State](../SpatialCameraState/DESIGN.md) | coordinates with | original decoration checkpoint | Restores independent spatial siblings | Root visibility gate stays withheld |
| [Optical Volume Transport](../../OpticalVolumeTransport/DESIGN.md) | depends on | shared storage lease | Admits all application snapshot copies | No private budget |
| [Native Line Rasterizer](../../NativeLineRasterizer/DESIGN.md) | depends on | original published lane restoration | Keeps mesh/model authority coherent | Validate capacities before restore |

## Architecture
```text
previous body wire state -> measure -> same-pool lease -> immutable checkpoint
camera decorations + calibration + section + body wires
  -> complete success -> release checkpoints
  -> failure -> restore original sibling source state -> withhold readiness
```

## Contracts and Invariants
Capture reserves application copy bytes before materialization, checks arithmetic
and reads only scoped native borrows. Original active vertex/index bytes survive
multiple updates. Restore validates all buffer capacities before the first write,
then restores original bytes, parts, draw lane and mounted model. The viewport
retains original raster dictionary and camera/section publication metadata until
all synchronous siblings and storage publication succeed.

## State, Ownership, and Lifecycle
All mutation is MainActor isolated. The immutable token owns the shared pool lease
until success or restoration ends. No pointer escapes and no checkpoint spans an
await or source replacement. Newly allocated unpublished rasters are released;
existing retained raster allocation remains counted.

## Failure, Concurrency, and Constraints
Cancellation, capacity mismatch, overflow and shared storage exhaustion propagate
as explicit failures. Restoration failure invalidates publication and preserves
the withheld readiness gate. Requested camera inputs remain active for retry.

## Verification and Change Impact
After source completion, run actual native/GPU base-success/delta-failure, pending
glyph, later calibration/section/wire failure, repeated raster updates and exact
capacity refusal. A source checkpoint is not runtime or frame-continuity evidence.
