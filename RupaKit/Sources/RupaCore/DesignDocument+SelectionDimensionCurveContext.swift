import Foundation
import SwiftCAD
import RupaCoreTypes

extension DesignDocument {
    func isSourceArcParameterPair(
        _ first: CurveParameterReference,
        _ second: CurveParameterReference
    ) throws -> Bool {
        guard first.curve == second.curve else {
            return false
        }
        let entityID = try sourceCurveEntityID(
            featureID: first.curve.featureID,
            curveIndex: first.curve.curveIndex
        )
        guard let feature = cadDocument.designGraph.nodes[first.curve.featureID],
              case let .sketch(sketch) = feature.operation,
              let entity = sketch.entities[entityID] else {
            throw EditorError(
                code: .referenceUnresolved,
                message: "Selection angle application could not resolve the source curve entity."
            )
        }
        if case .arc = entity {
            return true
        }
        return false
    }

    func isSourceLineParameterPair(
        _ first: CurveParameterReference,
        _ second: CurveParameterReference
    ) throws -> Bool {
        guard first.curve == second.curve else {
            return false
        }
        let entityID = try sourceCurveEntityID(
            featureID: first.curve.featureID,
            curveIndex: first.curve.curveIndex
        )
        guard let feature = cadDocument.designGraph.nodes[first.curve.featureID],
              case let .sketch(sketch) = feature.operation,
              let entity = sketch.entities[entityID] else {
            throw EditorError(
                code: .referenceUnresolved,
                message: "Selection distance application could not resolve the source curve entity."
            )
        }
        if case .line = entity {
            return true
        }
        return false
    }

    func isSourceLineWholeCurve(_ curve: CurveOutputReference) throws -> Bool {
        let entityID = try sourceCurveEntityID(
            featureID: curve.featureID,
            curveIndex: curve.curveIndex
        )
        guard let feature = cadDocument.designGraph.nodes[curve.featureID],
              case let .sketch(sketch) = feature.operation,
              let entity = sketch.entities[entityID] else {
            throw EditorError(
                code: .referenceUnresolved,
                message: "Selection point-line distance application could not resolve the source curve entity."
            )
        }
        if case .line = entity {
            return true
        }
        return false
    }

    func sourceLineDistanceContext(
        curve: CurveOutputReference
    ) throws -> SelectionDimensionSourceLineDistanceLineContext {
        let featureID = curve.featureID
        let entityID = try sourceCurveEntityID(
            featureID: featureID,
            curveIndex: curve.curveIndex
        )
        guard let feature = cadDocument.designGraph.nodes[featureID],
              case let .sketch(sketch) = feature.operation,
              case .line = sketch.entities[entityID] else {
            throw EditorError(
                code: .commandInvalid,
                message: "Selection point-line distance application currently supports whole source line references only."
            )
        }
        return SelectionDimensionSourceLineDistanceLineContext(
            featureID: featureID,
            entityID: entityID,
            curve: curve,
            plane: sketch.plane,
            target: try sourceSketchEntityTarget(featureID: featureID, entityID: entityID)
        )
    }

    func isSourceCircularRadiusDistance(
        center: CurveCenterReference,
        radialReference: CurveSubobjectReference
    ) throws -> Bool {
        let radialCurve: CurveOutputReference
        switch radialReference {
        case .whole(let curve):
            radialCurve = curve
        case .parameter(let parameter):
            radialCurve = parameter.curve
        case .span(let span):
            radialCurve = span.curve
        case .center, .controlPoint, .knot:
            return false
        }
        guard center.curve == radialCurve else {
            return false
        }
        let entityID = try sourceCurveEntityID(
            featureID: center.curve.featureID,
            curveIndex: center.curve.curveIndex
        )
        guard let feature = cadDocument.designGraph.nodes[center.curve.featureID],
              case let .sketch(sketch) = feature.operation,
              let entity = sketch.entities[entityID] else {
            throw EditorError(
                code: .referenceUnresolved,
                message: "Selection radius application could not resolve the source curve entity."
            )
        }
        switch entity {
        case .circle, .arc:
            return true
        case .point, .line, .spline:
            return false
        }
    }

    func radialCurveOutputReference(
        from reference: CurveSubobjectReference
    ) throws -> CurveOutputReference {
        switch reference {
        case .whole(let curve):
            return curve
        case .parameter(let parameter):
            return parameter.curve
        case .span(let span):
            return span.curve
        case .center, .controlPoint, .knot:
            throw EditorError(
                code: .commandInvalid,
                message: "Selection dimension application requires a radial curve point or whole curve reference."
            )
        }
    }

    func angleCurveOutputReference(
        from reference: CurveSubobjectReference
    ) throws -> CurveOutputReference {
        switch reference {
        case .whole(let curve):
            return curve
        case .parameter(let parameter):
            return parameter.curve
        case .span(let span):
            return span.curve
        case .center, .controlPoint, .knot:
            throw EditorError(
                code: .commandInvalid,
                message: "Selection angle application requires source curve references with tangent direction."
            )
        }
    }

    func sourceCurveEntityID(
        featureID: FeatureID,
        curveIndex: Int
    ) throws -> SketchEntityID {
        guard curveIndex >= 0 else {
            throw EditorError(
                code: .commandInvalid,
                message: "Selection dimension application requires a non-negative source curve index."
            )
        }
        let curveEntityIDs = try sourceCurveEntityIDs(featureID: featureID)
        guard curveIndex < curveEntityIDs.count else {
            throw EditorError(
                code: .referenceUnresolved,
                message: "Selection dimension application could not resolve the source curve index."
            )
        }
        return curveEntityIDs[curveIndex]
    }

    func sourceCurveEntityIDs(
        featureID: FeatureID
    ) throws -> [SketchEntityID] {
        guard let feature = cadDocument.designGraph.nodes[featureID],
              case let .sketch(sketch) = feature.operation else {
            throw EditorError(
                code: .referenceUnresolved,
                message: "Selection dimension application requires a source sketch feature."
            )
        }
        return sketch.entities
            .sorted(by: { $0.key.description < $1.key.description })
            .compactMap { entityID, entity in
                if case .point = entity {
                    return nil
                }
                return entityID
            }
    }

    func sketchSceneNodeID(
        featureID: FeatureID
    ) throws -> SceneNodeID {
        guard let sceneNodeID = productMetadata.sceneNodes.first(where: { _, node in
            node.reference == .sketch(featureID)
        })?.key else {
            throw EditorError(
                code: .referenceUnresolved,
                message: "Selection dimension application could not resolve the source sketch scene node."
            )
        }
        return sceneNodeID
    }

    func sourceSketchEntityTarget(
        featureID: FeatureID,
        entityID: SketchEntityID
    ) throws -> SelectionTarget {
        SelectionTarget(
            sceneNodeID: try sketchSceneNodeID(featureID: featureID),
            component: .sketchEntity(
                SelectionComponentID.sketchEntity(
                    featureID: featureID,
                    entityID: entityID
                )
            )
        )
    }
}
