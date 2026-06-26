import SwiftCAD

public struct JoinedCurveGroupSource: Codable, Hashable, Identifiable, Sendable {
    public var id: JoinedCurveGroupSourceID
    public var featureID: FeatureID
    public var memberEntityIDs: [SketchEntityID]
    public var firstJoinedReference: SketchReference
    public var secondJoinedReference: SketchReference
    public var constraintsBeforeJoin: [SketchConstraint]
    public var dimensionsBeforeJoin: [SketchDimension]
    public var constraintsAfterJoin: [SketchConstraint]
    public var dimensionsAfterJoin: [SketchDimension]

    public init(
        id: JoinedCurveGroupSourceID = JoinedCurveGroupSourceID(),
        featureID: FeatureID,
        memberEntityIDs: [SketchEntityID],
        firstJoinedReference: SketchReference,
        secondJoinedReference: SketchReference,
        constraintsBeforeJoin: [SketchConstraint],
        dimensionsBeforeJoin: [SketchDimension],
        constraintsAfterJoin: [SketchConstraint],
        dimensionsAfterJoin: [SketchDimension]
    ) {
        self.id = id
        self.featureID = featureID
        self.memberEntityIDs = memberEntityIDs
        self.firstJoinedReference = firstJoinedReference
        self.secondJoinedReference = secondJoinedReference
        self.constraintsBeforeJoin = constraintsBeforeJoin
        self.dimensionsBeforeJoin = dimensionsBeforeJoin
        self.constraintsAfterJoin = constraintsAfterJoin
        self.dimensionsAfterJoin = dimensionsAfterJoin
    }
}
