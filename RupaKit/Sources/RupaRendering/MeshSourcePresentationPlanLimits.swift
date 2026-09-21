import Foundation

/// Caller-lowerable ceilings for one presentation render plan.
///
/// A plan derives a world-transformed position buffer and a triangle index
/// buffer from an immutable scene, so the derived cost is charged before the
/// storage is reserved rather than discovered after it has grown. A caller may
/// lower any dimension; no caller may widen `hardMaximum`.
///
/// The pre-RealityKit Release baseline used the 12-body/6,284-segment dense fixture
/// and the 512-body/16-segment fixture. Each ceiling is the successful maximum
/// for that dimension plus 25%: 512 items, 150,840 positions, 301,632 triangles,
/// and 17,978,528 working bytes before headroom. The byte ceiling also remains
/// below 2.5% of the supported 8-GiB memory floor. These are admission bounds,
/// not a claim that RealityKit admits the same fixture or that offscreen
/// measurements prove whole-application acceptance. The plan now charges native
/// adapter inputs against these unchanged ceilings; opaque SDK allocations need
/// separate peak-memory evidence.
/// Raising a ceiling requires new boundary and signed-App performance evidence.
public struct MeshSourcePresentationPlanLimits: Equatable, Sendable {
    /// The module ceiling. No caller may exceed any of these values.
    public static let hardMaximum = MeshSourcePresentationPlanLimits(
        maxItemCount: 640,
        maxPositionCount: 188_550,
        maxTriangleCount: 377_040,
        maxRetainedByteCount: 22_473_160
    )

    /// The default viewport admission. Exceeding it is an explicit failure;
    /// this layer never changes source fidelity to make geometry fit.
    public static let standard = hardMaximum

    /// Fragments one frame's region visibility raster may charge.
    ///
    /// The raster answers a rectangle by reporting what the mounted frame
    /// draws at each of its device pixels, so what bounds its work is the
    /// projected coverage of the whole viewport and not the rectangle. One
    /// binning pass sums, over the projected triangles, the area of each
    /// bounding box intersected with the viewport; a frame above this count
    /// answers no rectangle at all rather than answering part of one.
    /// `RealityViewport/DESIGN.md` owns that admission and its refusal.
    ///
    /// The value is the largest fixture this raster was measured on plus the
    /// same 25% headroom the plan dimensions above carry. It does not inherit
    /// their acceptance criterion: those ceilings scale a fixture that passed
    /// the pre-RealityKit Release responsiveness baseline, and no
    /// responsiveness gate has yet admitted this raster at all, which is why
    /// `RealityViewport/DESIGN.md` states its wall cost as a fact and not as
    /// a budget. The largest measured was 106,588,977 fragments, from a
    /// hard-maximum 377,040-triangle plan filling a 3200-by-2000 device-pixel
    /// viewport at the densest admitted overdraw with 5,802 triangles
    /// straddling the perspective near plane. That measurement is an
    /// offscreen single-threaded kernel over synthetic geometry, not the
    /// mounted RealityKit path; it and the acceptance evidence it still owes
    /// are recorded there.
    ///
    /// Raising it admits deeper overdraw at a proportional cost in the time
    /// one pointer move spends; lowering it moves frames from answering into
    /// refusing, never into answering less completely.
    ///
    /// Unlike the plan dimensions above, neither region ceiling is
    /// caller-lowerable: each bounds what one mounted frame's raster may
    /// charge rather than one caller's admission budget, so `validate()` does
    /// not read them.
    public static let maxRegionFragmentCount = 133_236_221

    /// Bytes one frame's region visibility raster may retain.
    ///
    /// The raster retains its projected triangles, its bin entries, and one
    /// 32-bit identity per viewport device pixel; depth is scratch and is not
    /// retained. The ceiling is what the responsiveness plan byte budget
    /// leaves after a plan at `hardMaximum` has taken its share:
    /// The responsiveness acceptance policy owns that budget as 2.5% of the supported
    /// 8-GiB memory floor, which is 214,748,364 bytes, and this module cannot
    /// read it because it does not depend on that module, so the rule is
    /// restated here and changes with it. Subtracting
    /// `hardMaximum.maxRetainedByteCount` leaves 192,275,204.
    ///
    /// The maximum measured retained size was 71,192,936 bytes under the
    /// fixture above. The worst admissible projected set, twice
    /// `hardMaximum.maxTriangleCount` after the single perspective near clip
    /// at the projected stride, is 84,456,960 bytes before bins and identity
    /// pixels, so both sit inside this ceiling with room. The same offscreen
    /// caveat and re-recording condition apply.
    public static let maxRegionRetainedByteCount = 192_275_204

    public let maxItemCount: Int
    public let maxPositionCount: Int
    public let maxTriangleCount: Int
    public let maxRetainedByteCount: Int

    public init(
        maxItemCount: Int,
        maxPositionCount: Int,
        maxTriangleCount: Int,
        maxRetainedByteCount: Int
    ) {
        self.maxItemCount = maxItemCount
        self.maxPositionCount = maxPositionCount
        self.maxTriangleCount = maxTriangleCount
        self.maxRetainedByteCount = maxRetainedByteCount
    }

    /// Refuses a negative ceiling and any ceiling above the module hard
    /// maximum, so a caller can only lower what the module admits.
    public func validate() throws {
        try requireNonNegative(maxItemCount, named: "item")
        try requireNonNegative(maxPositionCount, named: "transformed position")
        try requireNonNegative(maxTriangleCount, named: "triangle")
        try requireNonNegative(maxRetainedByteCount, named: "retained byte")
        try requireWithinHardMaximum(
            maxItemCount,
            Self.hardMaximum.maxItemCount,
            named: "item"
        )
        try requireWithinHardMaximum(
            maxPositionCount,
            Self.hardMaximum.maxPositionCount,
            named: "transformed position"
        )
        try requireWithinHardMaximum(
            maxTriangleCount,
            Self.hardMaximum.maxTriangleCount,
            named: "triangle"
        )
        try requireWithinHardMaximum(
            maxRetainedByteCount,
            Self.hardMaximum.maxRetainedByteCount,
            named: "retained byte"
        )
    }

    private func requireNonNegative(_ value: Int, named name: String) throws {
        guard value >= 0 else {
            throw MeshSourcePresentationRenderError(
                code: .invalidLimit,
                message: "Presentation plan \(name) limit must not be negative."
            )
        }
    }

    private func requireWithinHardMaximum(
        _ value: Int,
        _ hardMaximum: Int,
        named name: String
    ) throws {
        guard value <= hardMaximum else {
            throw MeshSourcePresentationRenderError(
                code: .invalidLimit,
                message: """
                    Presentation plan \(name) limit \(value) exceeds the module \
                    hard maximum \(hardMaximum).
                    """
            )
        }
    }
}
