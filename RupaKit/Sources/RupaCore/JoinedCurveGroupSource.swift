import SwiftCAD

/// A joined curve made of member curves held end to end. Its first joint is stored as
/// `firstJoinedReference`, `secondJoinedReference` and `continuity`, with the constraints before
/// and after that joint was made; every later joint (a join of three or more curves, or a curve
/// joined onto an existing joined curve) is one of `additionalJoints`.
public struct JoinedCurveGroupSource: Codable, Hashable, Identifiable, Sendable {
    public var id: JoinedCurveGroupSourceID
    public var featureID: FeatureID
    public var memberEntityIDs: [SketchEntityID]
    public var firstJoinedReference: SketchReference
    public var secondJoinedReference: SketchReference
    public var continuity: SketchCurveJoinContinuity
    public var constraintsBeforeJoin: [SketchConstraint]
    public var dimensionsBeforeJoin: [SketchDimension]
    public var constraintsAfterJoin: [SketchConstraint]
    public var dimensionsAfterJoin: [SketchDimension]
    public var additionalJoints: [JoinedCurveGroupJoint]

    public init(
        id: JoinedCurveGroupSourceID = JoinedCurveGroupSourceID(),
        featureID: FeatureID,
        memberEntityIDs: [SketchEntityID],
        firstJoinedReference: SketchReference,
        secondJoinedReference: SketchReference,
        continuity: SketchCurveJoinContinuity,
        constraintsBeforeJoin: [SketchConstraint],
        dimensionsBeforeJoin: [SketchDimension],
        constraintsAfterJoin: [SketchConstraint],
        dimensionsAfterJoin: [SketchDimension],
        additionalJoints: [JoinedCurveGroupJoint] = []
    ) {
        self.id = id
        self.featureID = featureID
        self.memberEntityIDs = memberEntityIDs
        self.firstJoinedReference = firstJoinedReference
        self.secondJoinedReference = secondJoinedReference
        self.continuity = continuity
        self.constraintsBeforeJoin = constraintsBeforeJoin
        self.dimensionsBeforeJoin = dimensionsBeforeJoin
        self.constraintsAfterJoin = constraintsAfterJoin
        self.dimensionsAfterJoin = dimensionsAfterJoin
        self.additionalJoints = additionalJoints
    }

    /// Every joint, the first one first; the first joint's added constraints are the ones its
    /// after-join snapshot holds beyond its before-join snapshot.
    public var joints: [JoinedCurveGroupJoint] {
        let first = JoinedCurveGroupJoint(
            firstReference: firstJoinedReference,
            secondReference: secondJoinedReference,
            continuity: continuity,
            addedConstraints: JoinedCurveGroupJoint.constraintsAdded(to: constraintsBeforeJoin, in: constraintsAfterJoin)
        )
        return [first] + additionalJoints
    }

    private enum CodingKeys: String, CodingKey {
        case id, featureID, memberEntityIDs, firstJoinedReference, secondJoinedReference, continuity
        case constraintsBeforeJoin, dimensionsBeforeJoin, constraintsAfterJoin, dimensionsAfterJoin
        case additionalJoints
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(JoinedCurveGroupSourceID.self, forKey: .id)
        featureID = try container.decode(FeatureID.self, forKey: .featureID)
        memberEntityIDs = try container.decode([SketchEntityID].self, forKey: .memberEntityIDs)
        firstJoinedReference = try container.decode(SketchReference.self, forKey: .firstJoinedReference)
        secondJoinedReference = try container.decode(SketchReference.self, forKey: .secondJoinedReference)
        continuity = try container.decode(SketchCurveJoinContinuity.self, forKey: .continuity)
        constraintsBeforeJoin = try container.decode([SketchConstraint].self, forKey: .constraintsBeforeJoin)
        dimensionsBeforeJoin = try container.decode([SketchDimension].self, forKey: .dimensionsBeforeJoin)
        constraintsAfterJoin = try container.decode([SketchConstraint].self, forKey: .constraintsAfterJoin)
        dimensionsAfterJoin = try container.decode([SketchDimension].self, forKey: .dimensionsAfterJoin)
        // Documents saved before joins of three or more curves hold one joint only.
        additionalJoints = try container.decodeIfPresent([JoinedCurveGroupJoint].self, forKey: .additionalJoints) ?? []
    }
}
