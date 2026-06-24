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
        case .polySpline:
            return true
        case .faceLoopOffset:
            return true
        case .edgeOffset:
            return true
        case .faceKnife:
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

    var supersededBodyFeatureID: FeatureID? {
        switch self {
        case .sketch:
            return nil
        case .extrude:
            return nil
        case .revolve:
            return nil
        case .sweep:
            return nil
        case .polySpline:
            return nil
        case .faceLoopOffset(let feature):
            return feature.target.featureID
        case .edgeOffset(let feature):
            return feature.target.featureID
        case .faceKnife(let feature):
            return feature.target.featureID
        case .bridgeCurve:
            return nil
        case .curveEdit:
            return nil
        case .curveOffset:
            return nil
        case .curveTrim:
            return nil
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
