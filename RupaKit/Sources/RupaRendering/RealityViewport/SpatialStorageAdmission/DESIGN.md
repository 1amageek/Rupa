# Spatial Storage Admission

## Purpose and Scope
Child of [RealityViewport](../DESIGN.md), with no children. Composes async native
glyph preparation with the viewport's existing retained and in-flight byte pool.

## Responsibilities and Boundaries
The MainActor adapter owns callback ordering. OpticalVolumeFrameStore owns the
shared Mutex ledger and ARC storage leases. SpatialResources owns exact glyph
request identity, native resources, counters and publication. Opaque SDK-internal
driver allocation is outside application buffer accounting; inspected retained
geometry, application arrays and temporary ownership stay within the reserved
caller remainder.

## Related Designs
| Design | Relationship | Contract Used | Summary | Cautions |
|---|---|---|---|---|
| [RealityViewport](../DESIGN.md) | parent | current source lifecycle | Supplies mounted resources | Previous frame remains complete while glyphs prepare |
| [OpticalVolumeTransport](../../OpticalVolumeTransport/DESIGN.md) | depends on | preparation and StorageLease | Shares retained/in-flight admission | No private ceiling or release/reacquire transfer |

## Architecture
```text
current glyph key -> begin same viewport pool -> reserve caller remainder
 -> await actual SDK glyph -> inspect original buffers -> refine reservation
 -> exact-key/cancellation admission -> publish counters/resources
 -> atomically transfer reservation into external storage
```

## Contracts and Invariants
Reservation precedes SDK extrusion and application-owned candidates. A lease
refines atomically to inspected retained bytes. Publication and transfer contain
no suspension. A failure restores old glyph resources and counters; cancellation
or a superseded key releases the reservation and aborts the same preparation.
All callbacks use the original viewport pool and current external-storage count.

Initial and delta preparation receive the same optional adapter before native
population. Their candidate owns a preparation lifetime and refined lease until
`takePreparationLease` transfers both cleanup and publication responsibility to
the mounting owner. An abandoned candidate aborts its preparation on isolated
release. Aggregate source admission still includes inherited surface/base bytes;
`retainedNativeByteCount` reports only this resource's owned contribution, so the
viewport sums a retained plan, base and delta exactly once.

Static axis/label/ruler glyph resources are inspected once per created native
resource before application entity/cache publication. Original triangle/position
counts and retained bytes are added to the same cumulative source counters;
cached resources do not generate a second native resource. Population cannot
exceed its original shared reservation, including inherited source accounting.

Synchronous camera and placement entry points begin the same pool before any
native ribbon allocation. The one synchronous call converts its shared remainder
into a cumulative owner cap before allocation, so multiple new ribbon buffers
cannot each reuse the same unchanged lower remainder. It finishes with the actual
retained contribution.
Failure cleanup publishes retained candidate storage to the pool before returning
the original failure; if that accounting fails, the pool retains its explicit
failed-publication state and aborts the preparation. No remaining-budget query
is made outside an active preparation.

## State, Ownership, and Lifecycle
The adapter and callbacks are immutable MainActor values. The resource owns the
binding; one async task owns its lease until transfer or cleanup. Shutdown cancels
that task; ARC cleanup releases leases exactly once. No pointer escapes a native
buffer borrow.

## Failure, Concurrency, and Constraints
The shared lower pool retains Mutex synchronization on all accesses. MainActor
serializes key checks and resource publication, and suspension may invalidate
the key. A missing admission at a mounted optical boundary is an explicit caller
error. Standalone preparation uses its original source limits without pretending
to have a mounted viewport pool.

## Verification and Change Impact
Deferred until the whole source phase: run actual native glyph creation with
retained optical frames, coexistence limits, replacement during suspension,
cancellation/shutdown and failed transfer. Check old frame/source retention and
same-pool byte counts. Source wiring is not GPU allocation or runtime evidence.

Camera checkpoints reserve their exact application copies in the same pool before
capture. Lease-backed temporary bytes are not also reported as external native
storage. The original owner cap includes checkpoint coexistence. Local camera
wrappers restore a checkpoint on a throw or typed unsuccessful result; a root-held
checkpoint suppresses duplicate local capture and the root owns sibling rollback.
