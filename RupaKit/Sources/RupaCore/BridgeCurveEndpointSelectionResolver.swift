import SwiftCAD

public struct BridgeCurveEndpointSelectionResolver: Sendable {
    public init() {}

    public func endpoint(
        for target: SelectionTarget,
        in document: DesignDocument
    ) throws -> BridgeCurveEndpoint? {
        guard case .sketchEntity(let componentID) = target.component,
              let pointReference = componentID.sketchPointReference else {
            return nil
        }
        guard let sceneReference = document.productMetadata.sceneNodes[target.sceneNodeID]?.reference,
              sceneReference.kind == .sketch,
              sceneReference.featureID == pointReference.featureID else {
            return nil
        }
        guard let feature = document.cadDocument.designGraph.nodes[pointReference.featureID],
              case .sketch(let sketch) = feature.operation else {
            throw EditorError(
                code: .referenceUnresolved,
                message: "Bridge curve endpoint selection requires an editable sketch feature."
            )
        }
        guard isSupportedEndpointReference(pointReference.reference, in: sketch) else {
            return nil
        }
        return BridgeCurveEndpoint(reference: pointReference.reference)
    }

    private func isSupportedEndpointReference(
        _ reference: SketchReference,
        in sketch: Sketch
    ) -> Bool {
        switch reference {
        case let .lineStart(entityID),
             let .lineEnd(entityID):
            guard case .line = sketch.entities[entityID] else {
                return false
            }
            return true
        case let .arcStart(entityID),
             let .arcEnd(entityID):
            guard case .arc = sketch.entities[entityID] else {
                return false
            }
            return true
        case let .splineControlPoint(entityID, index):
            guard case .spline(let spline) = sketch.entities[entityID],
                  index == 0 || index == spline.controlPoints.count - 1 else {
                return false
            }
            return true
        case .entity,
             .circleCenter,
             .circleRadius,
             .arcCenter,
             .arcRadius:
            return false
        }
    }
}
