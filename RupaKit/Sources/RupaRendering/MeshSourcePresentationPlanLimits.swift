import Foundation

/// Caller-lowerable ceilings for one presentation render plan.
///
/// A plan derives a world-transformed position buffer and a triangle index
/// buffer from an immutable scene, so the derived cost is charged before the
/// storage is reserved rather than discovered after it has grown. A caller may
/// lower any dimension; no caller may widen `hardMaximum`.
///
/// Native Release measurements use the 12-body/6,284-segment dense fixture
/// and the 512-body/16-segment fixture. Each ceiling is the successful maximum
/// for that dimension plus 25%: 512 items, 150,840 positions, 301,632 triangles,
/// and 17,978,528 working bytes before headroom. The byte ceiling also remains
/// below 2.5% of the supported 8-GiB memory floor. These are admission bounds,
/// not a claim that offscreen measurements prove whole-application acceptance.
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
