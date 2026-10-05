import SwiftCAD

/// Explicit body-closure and aggregate contour capacities for original extraction.
public struct DrawingSilhouettePolicy: Codable, Equatable, Sendable {
    public let maximumSourceEntities: Int
    public let maximumSourceFaces: Int
    public let maximumProjectedSpans: Int
    public let maximumControlPointCount: Int
    public let maximumBoundaryCurveCount: Int
    public let maximumCells: Int
    public let maximumParameterWidth: ExactRationalCoefficient

    public init(maximumSourceEntities: Int, maximumSourceFaces: Int, maximumProjectedSpans: Int,
        maximumControlPointCount: Int, maximumBoundaryCurveCount: Int, maximumCells: Int, maximumParameterWidth: ExactRationalCoefficient) {
        self.maximumSourceEntities = maximumSourceEntities; self.maximumSourceFaces = maximumSourceFaces
        self.maximumProjectedSpans = maximumProjectedSpans; self.maximumControlPointCount = maximumControlPointCount
        self.maximumBoundaryCurveCount = maximumBoundaryCurveCount; self.maximumCells = maximumCells
        self.maximumParameterWidth = maximumParameterWidth
    }
    public func validate() throws {
        guard maximumSourceEntities > 0, maximumSourceFaces > 0, maximumProjectedSpans > 0,
              maximumControlPointCount > 0, maximumBoundaryCurveCount > 0, maximumCells > 0,
              maximumParameterWidth.isPositive else {
            throw EditorError(code: .commandInvalid, message: "Original silhouette capacities must be positive.")
        }
    }
}
