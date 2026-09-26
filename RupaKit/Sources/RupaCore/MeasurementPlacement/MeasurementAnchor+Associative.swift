import SwiftCAD
import RupaCoreTypes

extension MeasurementAnchor {
    /// The anchor that follows the geometry `candidate` snapped to, or `nil` when the snap names
    /// no geometry a saved measurement can follow.
    public static func associative(for candidate: SnapCandidate, role: Role) -> MeasurementAnchor? {
        if let topology = candidate.topologySource {
            let edgeParameter: Double? = switch candidate.kind {
            case .edgeStart: 0
            case .edgeEnd: 1
            case .edgeMidpoint: 0.5
            default: nil
            }
            if let edgeParameter, topology.kind == .edge {
                return .topologyEdgeParameter(
                    sceneNodeID: topology.sceneNodeID, component: topology.component,
                    subshapeID: topology.persistentName, referenceID: topology.referenceID,
                    parameter: edgeParameter, role: role
                )
            }
            switch (candidate.kind, topology.kind) {
            case (.topologyVertex, .vertex), (.faceCenter, .face):
                return .topologyReference(
                    sceneNodeID: topology.sceneNodeID, component: topology.component, kind: topology.kind,
                    subshapeID: topology.persistentName, referenceID: topology.referenceID, role: role
                )
            default:
                return nil
            }
        }
        guard let sketch = candidate.source else { return nil }
        let curveParameter: Double? = switch candidate.kind {
        case .lineStart, .arcStart, .splineStart: 0
        case .lineEnd, .arcEnd, .splineEnd: 1
        case .lineMidpoint, .arcMidpoint: 0.5
        default: nil
        }
        if let curveParameter {
            return .sketchCurveParameter(
                featureID: sketch.featureID, entityID: sketch.entityID, parameter: curveParameter,
                sceneNodeID: sketch.sceneNodeID, role: role
            )
        }
        let reference: SketchReference? = switch candidate.kind {
        case .circleCenter: .circleCenter(sketch.entityID)
        case .arcCenter: .arcCenter(sketch.entityID)
        case .sketchPoint: .entity(sketch.entityID)
        case .controlVertex: sketch.controlPointIndex.map { .splineControlPoint(entity: sketch.entityID, index: $0) }
        default: nil
        }
        return reference.map {
            .sketchReference(featureID: sketch.featureID, reference: $0, sceneNodeID: sketch.sceneNodeID, role: role)
        }
    }
}
