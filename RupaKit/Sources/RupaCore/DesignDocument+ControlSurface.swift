import Foundation
import SwiftCAD
import RupaCoreTypes

extension DesignDocument {
    /// The control surface a feature's control points are edited on: a B-spline surface source's,
    /// or the surface a Rebuild Face gives one face of a solid (`FaceRebuildMethod.given`, Raise
    /// Degree on a face of a solid); nil for any other feature.
    func editableControlSurface(of featureID: FeatureID) -> BSplineSurfaceFeature? {
        switch cadDocument.designGraph.nodes[featureID]?.operation {
        case .bSplineSurface(let surfaceFeature):
            return surfaceFeature
        case .faceRebuild(let rebuild):
            guard case let .given(surface) = rebuild.method, rebuild.faces.count == 1 else { return nil }
            return BSplineSurfaceFeature(surface: surface)
        default:
            return nil
        }
    }

    /// `feature` carrying `surfaceFeature` as its control surface: the B-spline source's surface
    /// feature, or the surface its Rebuild Face gives (whose face keeps its own edges as its
    /// boundary, so only the surface is taken).
    func withControlSurface(_ surfaceFeature: BSplineSurfaceFeature, in feature: FeatureNode) throws -> FeatureNode {
        var updated = feature
        switch feature.operation {
        case .bSplineSurface:
            updated.operation = .bSplineSurface(surfaceFeature)
        case .faceRebuild(var rebuild):
            guard case .given = rebuild.method else {
                throw EditorError(code: .referenceUnresolved, message: "A Rebuild Face gives no control surface to edit.")
            }
            rebuild.method = .given(surfaceFeature.surface)
            updated.operation = .faceRebuild(rebuild)
        default:
            throw EditorError(code: .referenceUnresolved, message: "The feature carries no control surface to edit.")
        }
        return updated
    }
}
