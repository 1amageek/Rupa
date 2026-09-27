import SwiftCAD

/// One joint of a joined curve: the two member ends it holds together, the continuity it keeps
/// there, and the constraints the join added for it, which Unjoin removes.
public struct JoinedCurveGroupJoint: Codable, Hashable, Sendable {
    public var firstReference: SketchReference
    public var secondReference: SketchReference
    public var continuity: SketchCurveJoinContinuity
    public var addedConstraints: [SketchConstraint]

    public init(
        firstReference: SketchReference,
        secondReference: SketchReference,
        continuity: SketchCurveJoinContinuity,
        addedConstraints: [SketchConstraint]
    ) {
        self.firstReference = firstReference
        self.secondReference = secondReference
        self.continuity = continuity
        self.addedConstraints = addedConstraints
    }

    /// The constraints `after` holds beyond `before`, each counted once.
    public static func constraintsAdded(to before: [SketchConstraint], in after: [SketchConstraint]) -> [SketchConstraint] {
        var remaining = before
        var added: [SketchConstraint] = []
        for constraint in after {
            if let index = remaining.firstIndex(of: constraint) {
                remaining.remove(at: index)
            } else {
                added.append(constraint)
            }
        }
        return added
    }
}
