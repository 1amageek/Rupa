import Foundation

/// Caller-lowerable ceilings for one presentation render plan.
///
/// A plan derives a world-transformed position buffer and a triangle index
/// buffer from an immutable scene, so the derived cost is charged before the
/// storage is reserved rather than discovered after it has grown. A caller may
/// lower any dimension; no caller may widen `hardMaximum`.
///
/// The ceilings are versioned values derived from the measured
/// `multi-body-cylinder-assembly` v1 fixture, which is 12 items, 150,840
/// transformed positions, 301,632 triangles, and 9.65 MB of derived storage.
/// Each dimension is that measurement multiplied by 32 and rounded up, so a
/// scene an order of magnitude larger than the measured worst case is still
/// admitted while an unbounded one is refused. Relaxing a value requires new
/// boundary, retained-byte, and signed-application responsiveness evidence; a
/// value is never raised merely to admit one scene.
public struct MeshSourcePresentationPlanLimits: Equatable, Sendable {
    /// The module ceiling. No caller may exceed any of these values.
    public static let hardMaximum = MeshSourcePresentationPlanLimits(
        maxItemCount: 512,
        maxPositionCount: 5_000_000,
        maxTriangleCount: 10_000_000,
        maxRetainedByteCount: 320 * 1024 * 1024
    )

    /// The default a viewport uses. Evaluation admission has already bounded
    /// the mesh that reaches a plan, so the plan ceiling is the last gate
    /// against a derived copy the process cannot hold rather than a second,
    /// tighter fidelity policy.
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
