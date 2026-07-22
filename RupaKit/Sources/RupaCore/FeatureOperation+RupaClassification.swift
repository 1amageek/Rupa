import SwiftCAD

extension FeatureOperation {
    var producesRenderableTopology: Bool {
        switch self {
        case .sketch:
            return false
        case .primitive:
            return true
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
        case .bSplineSurface:
            return true
        case .patchSurface:
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
        case .faceOffset,
             .faceMove,
             .edgeMove,
             .vertexMove,
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
             .bridgeSurface,
             .surfaceOffset,
             .surfaceTrim,
             .surfaceExtend,
             .surfaceMatch:
            return true
        case .bridgeCurve:
            return false
        case .curveEdit:
            return false
        case .curveOffset:
            return false
        case .curveTrim:
            return false
        case .curveExtend,
             .curveMatch:
            return false
        }
    }

    var supersededBodyFeatureIDs: Set<FeatureID> {
        switch self {
        case .sketch:
            return []
        case .primitive:
            return []
        case .extrude:
            return []
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
            guard feature.keepTools == false else {
                return []
            }
            return Set(feature.targets.map(\.featureID) + [feature.tool.featureID])
        case .polySpline:
            return []
        case .bSplineSurface:
            return []
        case .patchSurface:
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
        case .faceOffset(let feature):
            return [feature.target.featureID]
        case .faceMove(let feature):
            return [feature.target.featureID]
        case .edgeMove(let feature):
            return [feature.target.featureID]
        case .vertexMove(let feature):
            return [feature.target.featureID]
        case .linearPattern,
             .radialPattern,
             .gridPattern,
             .curveDrivenPattern:
            return []
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
        case .bridgeCurve:
            return []
        case .bridgeSurface:
            return []
        case .curveEdit:
            return []
        case .curveOffset:
            return []
        case .curveTrim:
            return []
        case .curveExtend,
             .curveMatch:
            return []
        case .surfaceOffset(let feature):
            return [feature.target.featureID]
        case .surfaceTrim(let feature):
            return [feature.target.featureID]
        case .surfaceExtend(let feature):
            return [feature.target.featureID]
        case .surfaceMatch(let feature):
            return [feature.source.featureID]
        }
    }
}

extension CADDocument {
    var hasActiveRenderableTopologyFeatures: Bool {
        designGraph.order.contains { featureID in
            guard let feature = designGraph.nodes[featureID], !feature.isSuppressed else {
                return false
            }
            return feature.operation.producesRenderableTopology
        }
    }
}
