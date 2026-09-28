import Foundation
import SwiftCAD

/// One end of a curve selected for Join Curves: aligned when it meets an end of another selected
/// curve of its sketch as exactly as Join requires, so Join takes it as a joint.
public struct SketchCurveJoinEndpointFeedback: Equatable, Sendable {
    public enum End: Equatable, Sendable {
        /// A line or arc end.
        case handle(SketchEntityPointHandle)
        /// A spline's first or last control point.
        case controlPoint(Int)
    }

    public var featureID: FeatureID
    public var entityID: SketchEntityID
    public var end: End
    public var isAligned: Bool

    public init(featureID: FeatureID, entityID: SketchEntityID, end: End, isAligned: Bool) {
        self.featureID = featureID
        self.entityID = entityID
        self.end = end
        self.isAligned = isAligned
    }
}

extension DesignDocument {
    /// Join Curves' endpoint feedback for the selected sketch curves: every end of each selected
    /// line, arc and spline, aligned or not by Join's own endpoint tolerance. Other selected
    /// components (points, circles, ends) take no part; fewer than two curves give no feedback,
    /// since Join needs two.
    public func sketchCurveJoinEndpointFeedback(targets: [SelectionTarget]) throws -> [SketchCurveJoinEndpointFeedback] {
        struct CurveEnd {
            var featureID: FeatureID
            var entityID: SketchEntityID
            var sketch: Sketch
            var reference: SketchReference
        }
        var ends: [CurveEnd] = []
        for target in targets {
            guard case .sketchEntity(let componentID) = target.component,
                  componentID.sketchEntityReference != nil else { continue }
            let selection = try editableSketchEntityBase(for: target, operationName: "Join Curves")
            switch selection.entity {
            case .line, .arc, .spline: break
            case .point, .circle: continue
            }
            for reference in try joinCurveEndpointCandidates(target: target, selection: selection, owner: "Join Curves") {
                ends.append(CurveEnd(featureID: selection.featureID, entityID: selection.entityID, sketch: selection.sketch, reference: reference))
            }
        }
        guard Set(ends.map(\.entityID)).count >= 2 else { return [] }
        return try ends.map { end in
            let isAligned = try ends.contains { other in
                guard other.featureID == end.featureID, other.entityID != end.entityID else { return false }
                return try joinCurveEndpointsAreAligned(end.reference, other.reference, sketch: end.sketch)
            }
            let feedbackEnd: SketchCurveJoinEndpointFeedback.End
            switch end.reference {
            case .lineStart: feedbackEnd = .handle(.lineStart)
            case .lineEnd: feedbackEnd = .handle(.lineEnd)
            case .arcStart: feedbackEnd = .handle(.arcStart)
            case .arcEnd: feedbackEnd = .handle(.arcEnd)
            case .splineControlPoint(_, let index): feedbackEnd = .controlPoint(index)
            case .entity, .circleCenter, .circleRadius, .arcCenter, .arcRadius:
                throw EditorError(code: .commandInvalid, message: "Join Curves produced an end that is not a curve end.")
            }
            return SketchCurveJoinEndpointFeedback(featureID: end.featureID, entityID: end.entityID, end: feedbackEnd, isAligned: isAligned)
        }
    }
}
