import SwiftCAD

extension FeatureOperation {
    var producesEvaluatedOutput: Bool {
        if producesRenderableTopology {
            return true
        }
        switch self {
        case .spatialPath,
             .bridgeCurve,
             .curveEdit,
             .curveOffset,
             .projectCurve,
             .curveTrim,
             .curveExtend,
             .curveMatch:
            return true
        case .involuteGear,
             .importedBRep,
             .sketch,
             .primitive,
             .extrude,
             .revolve,
             .sweep,
             .loft,
             .boolean,
             .chamfer,
             .fillet,
             .g2Blend,
             .setbackCorner,
             .shell,
             .thicken,
             .polySpline,
             .constrainedSurface,
             .bSplineSurface,
             .patchSurface,
             .faceLoopOffset,
             .edgeOffset,
             .faceKnife,
             .faceDelete,
             .faceDraft,
             .faceOffset,
             .faceMove,
             .edgeMove,
             .vertexMove,
             .topologyTransform,
             .linearPattern,
             .radialPattern,
             .gridPattern,
             .curveDrivenPattern,
             .mirror,
             .joinBodies,
             .unjoinBody,
             .extract,
             .wrap,
             .bridgeSurface,
             .surfaceOffset,
             .surfaceTrim,
             .surfaceExtend,
             .surfaceMatch,
             .surfaceFill:
            return false
        }
    }

    var producesRenderableTopology: Bool {
        switch self {
        case .involuteGear:
            return true
        case .importedBRep:
            return true
        case .sketch, .spatialPath:
            return false
        case .extrude:
            return true
        case .revolve:
            return true
        case .sweep:
            return true
        case .loft:
            return true
        case .boolean:
            return true
        case .polySpline:
            return true
        case .constrainedSurface, .bSplineSurface:
            return true
        case .faceLoopOffset:
            return true
        case .edgeOffset:
            return true
        case .faceKnife:
            return true
        case .faceDelete:
            return true
        case .faceDraft:
            return true
        case .bridgeCurve:
            return false
        case .curveEdit:
            return false
        case .curveOffset:
            return false
        case .curveTrim:
            return false
        case .primitive,
             .patchSurface,
             .bridgeSurface,
             .faceOffset,
             .faceMove,
             .edgeMove,
             .vertexMove,
             .topologyTransform,
             .linearPattern,
             .radialPattern,
             .gridPattern,
             .curveDrivenPattern,
             .chamfer,
             .fillet,
             .g2Blend,
             .setbackCorner,
             .shell,
             .thicken,
             .surfaceOffset,
             .surfaceTrim,
             .surfaceExtend,
             .surfaceMatch,
             .surfaceFill,
             .mirror,
             .joinBodies,
             .unjoinBody,
             .extract,
             .wrap:
            return true
        case .curveExtend,
             .curveMatch,
             .projectCurve:
            return false
        }
    }

    var supersededBodyFeatureIDs: Set<FeatureID> {
        switch self {
        case .involuteGear:
            return []
        case .importedBRep:
            return []
        case .sketch, .spatialPath:
            return []
        case .extrude(let source):
            return source.operation == .newBody || source.keepTools ? [] : Set(source.targets.map(\.featureID))
        case .revolve:
            return []
        case .sweep(let feature):
            // A boolean sweep replaces its target bodies (the kernel removes the
            // target topology unless keep-tools retains both operands), so the
            // targets must leave the measurable set exactly like standalone
            // boolean operands below.
            guard feature.options.booleanOperation != .newBody,
                  feature.options.keepTools == false else {
                return []
            }
            return Set(feature.targets.map(\.featureID))
        case .loft:
            return []
        case .boolean(let feature):
            // The result replaces its targets; Keep Tools keeps only the tools.
            return Set(feature.targets.map(\.featureID) + (feature.keepTools ? [] : feature.tools.map(\.featureID)))
        case .polySpline:
            return []
        case .constrainedSurface, .bSplineSurface:
            return []
        case .faceLoopOffset(let feature):
            return [feature.target.featureID]
        case .edgeOffset(let feature):
            return [feature.target.featureID]
        case .faceKnife(let feature):
            return [feature.target.featureID]
        case .faceDelete(let feature):
            return [feature.target.featureID]
        case .faceDraft(let feature):
            return [feature.target.featureID]
        case .bridgeCurve:
            return []
        case .curveEdit:
            return []
        case .curveOffset:
            return []
        case .curveTrim:
            return []
        case .faceOffset(let feature):
            return [feature.target.featureID]
        case .faceMove(let feature):
            return [feature.target.featureID]
        case .edgeMove(let feature):
            return [feature.target.featureID]
        case .vertexMove(let feature):
            return [feature.target.featureID]
        case .topologyTransform(let feature):
            return [feature.target.featureID]
        case .chamfer(let feature):
            return [feature.target.featureID]
        case .fillet(let feature):
            return [feature.target.featureID]
        case .g2Blend(let feature):
            return [feature.target.featureID]
        case .setbackCorner(let feature):
            return [feature.target.featureID]
        case .shell(let feature):
            return [feature.target.featureID]
        case .thicken(let feature):
            return [feature.target.featureID]
        case .surfaceOffset(let feature):
            return [feature.target.featureID]
        case .surfaceTrim(let feature):
            return [feature.target.featureID]
        case .surfaceExtend(let feature):
            return [feature.target.featureID]
        case .surfaceMatch(let feature):
            return [feature.source.featureID]
        // Join absorbs its source bodies into the merged body and unjoin
        // replaces its target with per-shell bodies, so their sources leave
        // the measurable set like boolean operands.
        case .joinBodies(let feature):
            return Set(feature.targets.map(\.featureID))
        case .unjoinBody(let feature):
            return [feature.target.featureID]
        // An extraction copies part of a body that stays: one extraction never replaces its
        // source. A source every component of which is extracted is replaced by its pieces, which
        // only the document's extractions together tell (`MeasurementService`).
        case .extract:
            return []
        // A wrap replaces its target unless it keeps it beside the deformed copy.
        case .wrap(let feature):
            return feature.keepsTarget ? [] : [feature.target.featureID]
        // Mirror rebuilds the identity and reflected instances as one
        // replacement body, so the source body is no longer independently
        // measurable after evaluation.
        case .mirror(let feature):
            return [feature.target.featureID]
        case .primitive,
             .patchSurface,
             .bridgeSurface,
             .linearPattern,
             .radialPattern,
             .gridPattern,
             .curveDrivenPattern,
             .surfaceFill,
             .curveExtend,
             .curveMatch,
             .projectCurve:
            return []
        }
    }
}

extension CADDocument {
    var hasActiveEvaluationFeatures: Bool {
        designGraph.order.contains { featureID in
            guard let feature = designGraph.nodes[featureID], !feature.isSuppressed else {
                return false
            }
            return feature.operation.producesEvaluatedOutput
        }
    }

    var hasActiveRenderableTopologyFeatures: Bool {
        designGraph.order.contains { featureID in
            guard let feature = designGraph.nodes[featureID], !feature.isSuppressed else {
                return false
            }
            return feature.operation.producesRenderableTopology
        }
    }
}
