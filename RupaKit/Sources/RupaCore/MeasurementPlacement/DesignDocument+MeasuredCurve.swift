import SwiftCAD
import RupaCoreTypes

/// A point a measurement starts or ends at, with the anchor that keeps it on its geometry.
public struct MeasuredCurvePoint: Equatable, Sendable {
    public var anchor: MeasurementAnchor
    public var worldPoint: Point3D
}

extension DesignDocument {
    /// The two points Measure measures on a selected edge or sketch curve: its ends, or for a closed
    /// edge or curve (a circle) two opposite points, so the distance is its diameter. `nil` when the
    /// target is not an edge or a whole sketch curve.
    public func measuredCurvePoints(
        for target: SelectionTarget,
        topology: TopologySnapshot?
    ) throws -> (start: MeasuredCurvePoint, end: MeasuredCurvePoint)? {
        func make(_ parameters: (Double, Double), _ anchor: (Double, MeasurementAnchor.Role) -> MeasurementAnchor) throws
            -> (start: MeasuredCurvePoint, end: MeasuredCurvePoint)? {
            let resolver = MeasurementAnchorWorldPointResolver()
            let first = anchor(parameters.0, .start)
            let second = anchor(parameters.1, .end)
            guard let a = try resolver.resolvedAnchor(first, in: self, topology: topology),
                  let b = try resolver.resolvedAnchor(second, in: self, topology: topology) else {
                throw EditorError(code: .referenceUnresolved, message: "The measured curve's points cannot be resolved.")
            }
            if (b.worldPoint - a.worldPoint).length <= ModelingTolerance.standard.distance, parameters.1 == 1 {
                // A closed curve: measure across it instead of from its start back to itself.
                return try make((0, 0.5), anchor)
            }
            return (MeasuredCurvePoint(anchor: first, worldPoint: a.worldPoint),
                    MeasuredCurvePoint(anchor: second, worldPoint: b.worldPoint))
        }
        switch target.component {
        case .edge:
            guard let topology,
                  let entry = topology.entries.first(where: { $0.kind == .edge && $0.selectionTarget() == target }) else {
                return nil
            }
            return try make((0, 1)) { parameter, role in
                .topologyEdgeParameter(
                    sceneNodeID: target.sceneNodeID, component: target.component, subshapeID: entry.subshapeID,
                    referenceID: entry.referenceID, parameter: parameter, role: role
                )
            }
        case .sketchEntity(let componentID):
            guard let reference = componentID.sketchEntityReference else { return nil }
            return try make((0, 1)) { parameter, role in
                .sketchCurveParameter(
                    featureID: reference.featureID, entityID: reference.entityID, parameter: parameter,
                    sceneNodeID: target.sceneNodeID, role: role
                )
            }
        default:
            return nil
        }
    }
}
