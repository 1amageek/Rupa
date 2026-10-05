# Optical Volume Transport

## Purpose and Scope
Own the native GPU transport of authored transmitting volumes in the mounted viewport. Parent: [RupaRendering](../DESIGN.md). No children. This is display-mesh optics; CAD geometry and tessellation fidelity remain their original owners.

## Responsibilities and Boundaries
The mounted RealityViewport supplies original admitted display triangles, occurrence materials, world-metre coordinates, preview transforms, camera transform, clipping half-space and remaining resource allowance. This component retains immutable Metal buffers and supplies a native RealityView postprocess effect. It cannot fabricate background geometry or substitute volume thickness with thin-film phase.

## Related Designs
| Design | Relationship | Contract Used | Summary | Cautions |
|---|---|---|---|---|
| [RupaRendering](../DESIGN.md) | parent | bounded display plan | Original triangles and occurrence authority | Charge original retained resources and optical candidates together |
| [RealityViewport](../RealityViewport/DESIGN.md) | coordinates with | mounted camera, material and publication | Native postprocess composition | Camera, preview, section, spatial primitive and appearance changes replace the complete optical input |

## Architecture
```text
admitted original occurrence triangles + resolved appearance + preview image
    -> checked immutable triangle/material buffers + stackless BVH
mounted camera + section + actual native color/depth buffers
    -> native PostProcessEffect -> GPU Snell/Fresnel/Beer-Lambert traversal
        -> complete optical result or explicit frame failure
```

## Contracts and Invariants
Coordinates are native render-origin-relative world metres. GPU radiance uses extended linear sRGB converted from the same calibrated NSColor authoring values used by the native material producer; alpha remains dimensionless. Authored thickness is the optical volume path length along the original entrance normal, in metres. The deterministic studio display law uses baseColor as a per-metre transmission tint and applies Beer-Lambert attenuation along `thickness / abs(dot(refractedDirection, entranceNormal))`. Zero thickness disables volume attenuation. This is an explicit viewport material response, not an exact spectroscopic simulation. Refraction uses authored IOR, original face winding and the actual next interface. Total internal reflection follows the original reflected ray. Nested medium transitions are tracked by occurrence identity; inconsistent transitions fail. A native section cap is the actual ray/half-space intersection admitted only when original closed display-triangle incidence proves that occurrence contains the cap point. Its outward normal is opposite the retained half-space normal. A camera inside a retained volume uses the remaining original forward/backward interface distance ratio for the authored normal thickness; it cannot silently omit attenuation.

A ray with no scene hit consumes the exact original theme/custom canvas linear-RGBA value provided by ViewportCanvasBackground, which is also the SwiftUI canvas producer. Its authored alpha is retained; an unknown backdrop behind a partially transparent canvas is not replaced with an invented opaque environment. Volume tint attenuates the known canvas radiance, while remaining alpha follows the existing compositor response. A scene hit uses that occurrence's original resolved material and the original native flat shading normal. Incidence and medium transitions use the oriented geometric face normal; studio lighting uses the retained native normal, including the preview producer's original Float cross product. Section caps use their clipping-plane normal for both laws. Visible original raster shading can be retained only with a matching projected depth; otherwise the explicit same-studio material law shades the actual ray hit. No screen-edge clamp is a background-ray result.

Only pixels whose first original retained scene hit has active volume transport are replaced. Native color/depth for all other pixels is retained. Section clipping, scene order, preview winding, original occurrence identity and frame revision must agree with the mounted native scene.

## Runtime Flows
Native glyph preparation is keyed by the original styled text and preserves the previous complete mounted frame while `glyphsPreparing` is pending. Owner release cancels glyph preparation before releasing its native hierarchy. Actual drawn native triangle primitives retain their original unlit radiance, depth-read and section contracts in the optical snapshot; native lines require the same drawn coverage producer rather than an optical-only geometric proxy.

The MainActor scene owner constructs and admits one immutable optical candidate before publishing an appearance. The native effect receives RealityKit's command buffer and textures; GPU failure or exhausted work is retained in a Mutex-owned status and reported through the mounted frame's existing failure receiver. A changed scene never borrows a previous scene's authority. GPU success is confirmed by command-buffer completion, not encoding. Each complete camera/world matrix, clipping, shading, viewport size/backing scale and camera revision capture has a distinct Mutex status. A previous camera result cannot admit a changed camera frame. Volume reflection uses the explicit studio law regardless of whether a candidate native hierarchy is temporarily hidden, so publication visibility does not change transport authority.

## State, Ownership, and Lifecycle
Metal buffers are immutable after publication and retained by each in-flight effect. Native command buffers own execution ordering. Shared failure status is protected by Synchronization.Mutex; GPU completion callbacks perform no MainActor mutation. Input staging copies occur only at the explicit GPU upload boundary and their coexistence is charged. No raw pointers escape a scoped array borrow.

## Failure, Concurrency, and Constraints
Checked source triangle/node/material byte counts include CPU construction and GPU retention. Caller limits bound ray interactions, traversal work and retained/temporary bytes; exhaustion is a typed resource failure, never successful truncated radiance. Each actual node visit, triangle inspection, occurrence inspection and medium-stack search, insertion or removal visit consumes the same per-pixel traversal allowance before execution. Admission checks the remaining count before incrementing, including a UInt32.max allowance, so counter wrap cannot renew the allowance. Finite source vertices alone do not prove finite ray arithmetic: original edge differences, cross/dot products, barycentric quotients, hit positions and final radiance/coverage are checked before using them as intersection or publication authority. Invalid Float conversion, singular preview transform, malformed incidence, device/pipeline/allocation failure, stale input and cancellation are explicit failures. The PostProcessEffect callback cannot throw; it records its failure for the existing frame status path and withholds success authority.

## Verification and Change Impact
Verification begins only after the full source phase. Real xcodebuild Metal execution must cover thickness-dependent attenuation, IOR-dependent background displacement, total internal reflection, nested volumes, actual scene hits outside the primary view, authored theme/custom alpha background, clipping/preview/camera replacement, failed and exhausted work, and atomic appearance retention. Rebuild/save/restart of the intended Rupa executable and document remains required. No source change or shader encoding alone proves this contract.

### Shared source and frame storage admission

One viewport-owned `OpticalVolumeFrameStore` serializes source preparation,
original native storage reservations, every retained optical scene, all GPU
scratch and retained image leases. A MainActor source preparation guard freezes
new GPU scratch admission while original and candidate native storage coexist.
Already admitted GPU work completes normally. Candidate source/GPU buffers use
ARC-owned immutable storage leases, also captured by command completion, so a
replaced effect remains charged until its actual GPU lifetime ends. Preparation
uses the same remaining-byte receipt; publication updates actual external native
storage before reopening GPU admission. A temporarily frozen callback publishes
a retained failure frame and pending status rather than a successful new frame.
No effect keeps a stale private byte allowance after preview or raster growth.

Capture identity also retains whether the native surface hierarchy is visible,
because depth/source-colour reuse depends on that authority. A failed capture is
reported on unchanged inputs; changed original capture inputs create a new
isolated status and can recover without borrowing earlier completion.
