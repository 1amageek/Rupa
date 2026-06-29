import SwiftCAD

extension FeatureOperation {
    var producesRenderableTopology: Bool {
        switch self {
        case .sketch:
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
        case .bSplineSurface:
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
        }
    }

    var supersededBodyFeatureIDs: Set<FeatureID> {
        switch self {
        case .sketch:
            return []
        case .extrude:
            return []
        case .revolve:
            return []
        case .sweep:
            return []
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
