import Foundation
import SwiftCAD
import RupaCoreTypes

extension DesignDocument {
    /// Raise Surface Degree on the surfaces behind the selected faces and objects, as one step:
    /// each B-spline surface's degree rises by one in both directions, exactly (Swift-CAD degree
    /// elevation), so its shape, parameterization and trims stay as they are while it gains
    /// control points. Several targets on one surface raise it once.
    public mutating func raiseSurfaceDegree(
        targets: [SelectionTarget],
        objectRegistry: ObjectTypeRegistry = .builtIn
    ) throws {
        let operationName = "Raise Surface Degree"
        guard targets.isEmpty == false else {
            throw EditorError(code: .commandInvalid, message: "\(operationName) requires a face or a surface.")
        }
        var sources: [FeatureID] = []
        for target in targets {
            switch target.component {
            case .object, .face: break
            default:
                throw EditorError(code: .commandInvalid, message: "\(operationName) raises the surface of a face or an object.")
            }
            guard let featureID = productMetadata.sceneNodes[target.sceneNodeID]?.reference?.featureID,
                  let source = surfaceControlSourceFeatureID(for: featureID),
                  case .bSplineSurface = cadDocument.designGraph.nodes[source]?.operation else {
                // FIXME(INCOMPLETE_IMPLEMENTATION): Plasticity raises the surface of any face or
                // solid, turning it into control points first. Rupa edits control points only on
                // B-spline surface sources, so a face of any other body (a box's plane, a
                // cylinder, a PolySpline patch) is refused here from the palette and Shift-S.
                // This is complete only when every face can be given an editable exact B-spline
                // surface in its body and raised there.
                throw EditorError(
                    code: .commandInvalid,
                    message: "\(operationName) raises B-spline surfaces; this face has no control points to raise."
                )
            }
            if sources.contains(source) == false { sources.append(source) }
        }
        let tolerance = modelingSettings.tolerance
        let previous = self
        var didCommit = false
        defer { if !didCommit { self = previous } }
        for source in sources {
            guard var feature = cadDocument.designGraph.nodes[source],
                  case .bSplineSurface(var surfaceFeature) = feature.operation else {
                throw EditorError(code: .referenceUnresolved, message: "\(operationName) lost the surface it raises.")
            }
            do {
                surfaceFeature.surface = try surfaceFeature.surface
                    .elevatingDegree(direction: .u, tolerance: tolerance)
                    .elevatingDegree(direction: .v, tolerance: tolerance)
            } catch {
                throw EditorError(code: .commandInvalid, message: "\(operationName) could not raise the surface: \(error).")
            }
            try surfaceFeature.validate(tolerance: tolerance)
            feature.operation = .bSplineSurface(surfaceFeature)
            try cadDocument.replaceFeature(feature, tolerance: tolerance)
            recordSurfaceShape(of: source, surfaceFeature.surface)
        }
        try validate(objectRegistry: objectRegistry)
        didCommit = true
    }

    /// Keeps the degree and control-point counts the objects of `featureID` list in step with its
    /// surface.
    mutating func recordSurfaceShape(of featureID: FeatureID, _ surface: BSplineSurface3D) {
        for (id, node) in productMetadata.sceneNodes where node.reference?.featureID == featureID && node.object != nil {
            productMetadata.sceneNodes[id]?.object?.properties["surface.degree.u"] = .integer(surface.uDegree)
            productMetadata.sceneNodes[id]?.object?.properties["surface.degree.v"] = .integer(surface.vDegree)
            productMetadata.sceneNodes[id]?.object?.properties["control.point.u"] = .integer(surface.uControlPointCount)
            productMetadata.sceneNodes[id]?.object?.properties["control.point.v"] = .integer(surface.vControlPointCount)
        }
    }
}
