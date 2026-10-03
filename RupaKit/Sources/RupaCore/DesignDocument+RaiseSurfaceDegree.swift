import Foundation
import SwiftCAD
import RupaCoreTypes

extension DesignDocument {
    /// Raise Surface Degree on the surfaces behind the selected faces and objects, as one step:
    /// each B-spline surface's degree rises by one in both directions, exactly (Swift-CAD degree
    /// elevation), so its shape, parameterization and trims stay as they are while it gains
    /// control points. Several targets on one surface raise it once. A face of any other body (a
    /// box's plane, Plasticity's Raise Degree on a face of a solid) is given its surface as an exact
    /// B-spline first (Swift-CAD `FaceBSplineSurfaceConverter`), raised and kept by a Rebuild Face
    /// with that surface (`FaceRebuildMethod.given`); raising that face again raises the surface
    /// the Rebuild Face gives it.
    public mutating func raiseSurfaceDegree(
        targets: [SelectionTarget],
        objectRegistry: ObjectTypeRegistry = .builtIn,
        currentEvaluation: DocumentEvaluationContext? = nil,
        currentGeneration: DocumentGeneration? = nil
    ) throws {
        let operationName = "Raise Surface Degree"
        guard targets.isEmpty == false else {
            throw EditorError(code: .commandInvalid, message: "\(operationName) requires a face or a surface.")
        }
        var sources: [FeatureID] = []
        var bodyFaces: [SelectionTarget] = []
        for target in targets {
            switch target.component {
            case .object, .face: break
            default:
                throw EditorError(code: .commandInvalid, message: "\(operationName) raises the surface of a face or an object.")
            }
            guard let featureID = productMetadata.sceneNodes[target.sceneNodeID]?.reference?.featureID else {
                throw EditorError(code: .referenceUnresolved, message: "\(operationName) found no body behind the selection.")
            }
            if let source = surfaceControlSourceFeatureID(for: featureID), case .bSplineSurface = cadDocument.designGraph.nodes[source]?.operation {
                if sources.contains(source) == false { sources.append(source) }
                continue
            }
            guard case .face = target.component else {
                // FIXME(INCOMPLETE_IMPLEMENTATION): Plasticity's page also raises a whole solid,
                // every face given control points; Rupa raises one face of a solid at a time and
                // refuses the object here from the palette and Shift-S. Complete when a solid's
                // faces are raised together, verified by a box raised whole keeping its volume.
                throw EditorError(code: .commandInvalid, message: "\(operationName) raises a face of a solid; select its face.")
            }
            if bodyFaces.contains(target) == false { bodyFaces.append(target) }
        }
        let tolerance = modelingSettings.tolerance
        let previous = self
        var didCommit = false
        defer { if !didCommit { self = previous } }
        func raised(_ surface: BSplineSurface3D) throws -> BSplineSurface3D {
            do {
                return try surface.elevatingDegree(direction: .u, tolerance: tolerance).elevatingDegree(direction: .v, tolerance: tolerance)
            } catch {
                throw EditorError(code: .commandInvalid, message: "\(operationName) could not raise the surface: \(error).")
            }
        }
        for source in sources {
            guard var feature = cadDocument.designGraph.nodes[source],
                  case .bSplineSurface(var surfaceFeature) = feature.operation else {
                throw EditorError(code: .referenceUnresolved, message: "\(operationName) lost the surface it raises.")
            }
            surfaceFeature.surface = try raised(surfaceFeature.surface)
            try surfaceFeature.validate(tolerance: tolerance)
            feature.operation = .bSplineSurface(surfaceFeature)
            try cadDocument.replaceFeature(feature, tolerance: tolerance)
            recordSurfaceShape(of: source, surfaceFeature.surface)
        }
        for target in bodyFaces {
            let evaluated = try DocumentEvaluationContextResolver().evaluatedDocument(
                document: self, objectRegistry: objectRegistry,
                currentEvaluation: sources.isEmpty ? currentEvaluation : nil, currentGeneration: sources.isEmpty ? currentGeneration : nil,
                failurePrefix: "\(operationName) requires the face's body evaluated"
            )
            guard let featureID = productMetadata.sceneNodes[target.sceneNodeID]?.reference?.featureID,
                  case .face(let componentID) = target.component else {
                throw EditorError(code: .referenceUnresolved, message: "\(operationName) found no body behind the face.")
            }
            // The face a Rebuild Face already gives a surface: that surface rises.
            if var feature = cadDocument.designGraph.nodes[featureID], case .faceRebuild(var rebuild) = feature.operation,
               case let .given(surface) = rebuild.method, let subshapeID = componentID.generatedTopologySubshapeID,
               let given = rebuild.faces.first,
               evaluated.lineage[subshapeID]?.parents.contains(given.subshapeID) == true {
                rebuild.method = .given(try raised(surface))
                feature.operation = .faceRebuild(rebuild)
                try cadDocument.replaceFeature(feature, tolerance: tolerance)
                continue
            }
            let topology = try TopologySnapshotService().snapshot(
                document: self, objectRegistry: objectRegistry,
                currentEvaluation: sources.isEmpty ? currentEvaluation : nil, currentGeneration: sources.isEmpty ? currentGeneration : nil
            )
            let reference = try stableReference(of: target, kind: .face, in: topology, operationName: operationName)
            let surface: BSplineSurface3D
            do {
                surface = try FaceBSplineSurfaceConverter().surface(of: reference, in: evaluated)
            } catch {
                throw EditorError(code: .commandInvalid, message: "\(operationName): \(error)")
            }
            _ = try rebuildFaces(
                name: "Raise Degree", targets: [target], method: .given(try raised(surface)), extendU: 0, extendV: 0, shrinks: false,
                objectRegistry: objectRegistry,
                currentEvaluation: sources.isEmpty ? currentEvaluation : nil, currentGeneration: sources.isEmpty ? currentGeneration : nil
            )
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
