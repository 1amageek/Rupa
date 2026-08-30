import Foundation

/// Caller-lowerable limits for one MeshSource triangulation operation.
public struct MeshTriangulationLimits: Equatable, Sendable {
    public static let hardMaximum = MeshTriangulationLimits(
        maxFaceCornerCount: 16_384,
        maxNonConvexWorkUnits: 1_000_000
    )

    public static let standard = MeshTriangulationLimits(
        maxFaceCornerCount: 16_384,
        maxNonConvexWorkUnits: 1_000_000
    )

    public let maxFaceCornerCount: Int
    public let maxNonConvexWorkUnits: Int

    public init(
        maxFaceCornerCount: Int,
        maxNonConvexWorkUnits: Int
    ) {
        self.maxFaceCornerCount = maxFaceCornerCount
        self.maxNonConvexWorkUnits = maxNonConvexWorkUnits
    }
}
