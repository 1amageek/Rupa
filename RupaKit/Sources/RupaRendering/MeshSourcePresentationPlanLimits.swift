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

    /// Cells per axis of the grid a selection rectangle samples a candidate on.
    ///
    /// This ceiling lives here because it bounds the native surface queries one
    /// rectangle update may spend, which is a budget of the same plan the other
    /// ceilings bound. It is not a measured value. `ViewportRectangleSampleGrid`
    /// samples each cell inside the candidate's coverage of it, and an
    /// axis-aligned visible window spanning at least two cells always contains
    /// a whole cell, whose middle that window then contains, so a candidate
    /// showing such a window inside the rectangle always has a sample in it
    /// whatever its tessellation. Four per axis makes that window a quarter of
    /// the rectangle.
    ///
    /// It is also the only thing that decides which narrower windows the
    /// rectangle can find at all: one sample per cell loses a visible sliver
    /// thinner than a cell whatever the tessellation, so raising this count is
    /// the only way to narrow that gap, and it raises the query ceiling in
    /// proportion. Lowering it does the reverse. `RupaRendering/DESIGN.md` owns
    /// that soundness-without-completeness contract.
    ///
    /// Unlike the plan dimensions below it, this is not caller-lowerable: the
    /// guarantee it states is a property of the sampling rule and not of one
    /// caller's admission budget, so `validate()` does not read it.
    public static let rectangleSampleGridDivisions = 4

    /// Native surface queries one selection rectangle update may spend on a
    /// single candidate: at most one per grid cell.
    ///
    /// The occurrence rectangle has one candidate per plan item, so its
    /// plan-wide ceiling is this count times `maxItemCount`. The CAD sub-shape
    /// rectangle asks per sub-shape rather than per item, so this per-candidate
    /// ceiling is the bound that path states.
    public static var maxRectangleSurfaceQueryCountPerCandidate: Int {
        rectangleSampleGridDivisions * rectangleSampleGridDivisions
    }

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
