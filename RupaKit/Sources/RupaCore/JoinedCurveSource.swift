import SwiftCAD

public struct JoinedCurveSource: Codable, Hashable, Identifiable, Sendable {
    public var id: JoinedCurveSourceID
    public var featureID: FeatureID
    public var retainedEntityID: SketchEntityID
    public var restoredEntityID: SketchEntityID
    public var retainedOriginalLine: SketchLine
    public var restoredOriginalLine: SketchLine
    public var joinedLine: SketchLine
    public var retainedSharedReference: SketchReference
    public var restoredSharedReference: SketchReference
    public var restoredOuterReference: SketchReference
    public var migratedRestoredOuterReference: SketchReference
    public var constraintsBeforeJoin: [SketchConstraint]
    public var dimensionsBeforeJoin: [SketchDimension]
    public var constraintsAfterJoin: [SketchConstraint]
    public var dimensionsAfterJoin: [SketchDimension]

    public init(
        id: JoinedCurveSourceID = JoinedCurveSourceID(),
        featureID: FeatureID,
        retainedEntityID: SketchEntityID,
        restoredEntityID: SketchEntityID,
        retainedOriginalLine: SketchLine,
        restoredOriginalLine: SketchLine,
        joinedLine: SketchLine,
        retainedSharedReference: SketchReference,
        restoredSharedReference: SketchReference,
        restoredOuterReference: SketchReference,
        migratedRestoredOuterReference: SketchReference,
        constraintsBeforeJoin: [SketchConstraint],
        dimensionsBeforeJoin: [SketchDimension],
        constraintsAfterJoin: [SketchConstraint],
        dimensionsAfterJoin: [SketchDimension]
    ) {
        self.id = id
        self.featureID = featureID
        self.retainedEntityID = retainedEntityID
        self.restoredEntityID = restoredEntityID
        self.retainedOriginalLine = retainedOriginalLine
        self.restoredOriginalLine = restoredOriginalLine
        self.joinedLine = joinedLine
        self.retainedSharedReference = retainedSharedReference
        self.restoredSharedReference = restoredSharedReference
        self.restoredOuterReference = restoredOuterReference
        self.migratedRestoredOuterReference = migratedRestoredOuterReference
        self.constraintsBeforeJoin = constraintsBeforeJoin
        self.dimensionsBeforeJoin = dimensionsBeforeJoin
        self.constraintsAfterJoin = constraintsAfterJoin
        self.dimensionsAfterJoin = dimensionsAfterJoin
    }
}
