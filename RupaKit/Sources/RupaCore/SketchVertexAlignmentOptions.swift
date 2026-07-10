import SwiftCAD

public struct SketchVertexAlignmentOptions: Codable, Equatable, Sendable {
    public var continuity: SketchVertexAlignmentContinuity
    public var referenceParameter: CADExpression?
    public var targetContinuityDistance: CADExpression?
    public var referenceContinuityDistance: CADExpression?

    public init(
        continuity: SketchVertexAlignmentContinuity = .g0,
        referenceParameter: CADExpression? = nil,
        targetContinuityDistance: CADExpression? = nil,
        referenceContinuityDistance: CADExpression? = nil
    ) {
        self.continuity = continuity
        self.referenceParameter = referenceParameter
        self.targetContinuityDistance = targetContinuityDistance
        self.referenceContinuityDistance = referenceContinuityDistance
    }
}
