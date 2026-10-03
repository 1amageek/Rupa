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
    /// the Rebuild Face gives it. An object of such a body has every face raised so.
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
        var bodyObjects: [SceneNodeID] = []
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
                // A whole solid: every face of it (Plasticity's Raise Degree on a solid).
                if bodyObjects.contains(target.sceneNodeID) == false { bodyObjects.append(target.sceneNodeID) }
                continue
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
        for nodeID in bodyObjects {
            try raiseEveryFace(
                of: nodeID, raised: raised, operationName: operationName, objectRegistry: objectRegistry,
                currentEvaluation: sources.isEmpty && bodyFaces.isEmpty ? currentEvaluation : nil,
                currentGeneration: sources.isEmpty && bodyFaces.isEmpty ? currentGeneration : nil
            )
        }
        try validate(objectRegistry: objectRegistry)
        didCommit = true
    }

    /// The Rebuild Face giving the face `subshape` (a face of the object under `tip`) its surface:
    /// the face traced back through the lineage of the Rebuild Faces giving surfaces under the
    /// object to the one that names it; nil when none does.
    func givenSurfaceFeature(for subshape: SubshapeID, under tip: FeatureID, in evaluated: EvaluatedDocument) -> FeatureID? {
        var given: [SubshapeID: FeatureID] = [:]
        var base = tip
        while case .faceRebuild(let rebuild)? = cadDocument.designGraph.nodes[base]?.operation,
              case .given = rebuild.method, rebuild.faces.count == 1 {
            given[rebuild.faces[0].subshapeID] = base
            base = rebuild.target.featureID
        }
        var current = subshape
        var visited = Set<SubshapeID>()
        while visited.insert(current).inserted {
            if let feature = given[current] { return feature }
            guard current.featureID != base, let parent = evaluated.lineage[current]?.parents.first else { return nil }
            current = parent
        }
        return nil
    }

    /// Every face of a solid raised at once: a face a Rebuild Face already gives a surface has that
    /// surface raised in place; every other face is given its own surface raised, each by a Rebuild
    /// Face naming the face as the body under those Rebuild Faces made it (found through them by
    /// lineage), appended one after another.
    private mutating func raiseEveryFace(
        of nodeID: SceneNodeID,
        raised: (BSplineSurface3D) throws -> BSplineSurface3D,
        operationName: String,
        objectRegistry: ObjectTypeRegistry,
        currentEvaluation: DocumentEvaluationContext?,
        currentGeneration: DocumentGeneration?
    ) throws {
        guard let tip = productMetadata.sceneNodes[nodeID]?.reference?.featureID else {
            throw EditorError(code: .referenceUnresolved, message: "\(operationName) found no body behind the object.")
        }
        let evaluated = try DocumentEvaluationContextResolver().evaluatedDocument(
            document: self, objectRegistry: objectRegistry, currentEvaluation: currentEvaluation, currentGeneration: currentGeneration,
            failurePrefix: "\(operationName) requires the solid evaluated"
        )
        let topology = try TopologySnapshotService().snapshot(
            document: self, objectRegistry: objectRegistry, currentEvaluation: currentEvaluation, currentGeneration: currentGeneration
        )
        // The Rebuild Faces giving faces surfaces, from the tip back to the body under them.
        var given: [SubshapeID: FeatureID] = [:]
        var base = tip
        while case .faceRebuild(let rebuild)? = cadDocument.designGraph.nodes[base]?.operation,
              case .given = rebuild.method, rebuild.faces.count == 1 {
            given[rebuild.faces[0].subshapeID] = base
            base = rebuild.target.featureID
        }
        var inPlace: [FeatureID] = []
        var added: [(reference: StableSubshapeReference, surface: BSplineSurface3D)] = []
        for entry in topology.entries where entry.kind == .face && entry.sceneNodeID == nodeID.description {
            guard let current = entry.stableReference else {
                throw EditorError(code: .referenceUnresolved, message: "\(operationName) could not name a face of the solid.")
            }
            // Back through the lineage to a face given a surface, or to the face as the body made it.
            var subshape = current.subshapeID
            var raisedBy = given[subshape]
            var visited = Set<SubshapeID>()
            while raisedBy == nil, subshape.featureID != base, visited.insert(subshape).inserted,
                  let parent = evaluated.lineage[subshape]?.parents.first {
                subshape = parent
                raisedBy = given[subshape]
            }
            if let raisedBy {
                if inPlace.contains(raisedBy) == false { inPlace.append(raisedBy) }
                continue
            }
            guard subshape.featureID == base else {
                throw EditorError(code: .referenceUnresolved, message: "\(operationName) could not trace a face of the solid to its body.")
            }
            let surface: BSplineSurface3D
            do {
                surface = try FaceBSplineSurfaceConverter().surface(of: current, in: evaluated)
            } catch {
                throw EditorError(code: .commandInvalid, message: "\(operationName): \(error)")
            }
            added.append((StableSubshapeReference(subshapeID: subshape, geometrySignature: current.geometrySignature), try raised(surface)))
        }
        let tolerance = modelingSettings.tolerance
        for featureID in inPlace {
            guard var feature = cadDocument.designGraph.nodes[featureID], case .faceRebuild(var rebuild) = feature.operation,
                  case let .given(surface) = rebuild.method else {
                throw EditorError(code: .referenceUnresolved, message: "\(operationName) lost a face's surface it raises.")
            }
            rebuild.method = .given(try raised(surface))
            feature.operation = .faceRebuild(rebuild)
            try cadDocument.replaceFeature(feature, tolerance: tolerance)
        }
        var target = tip
        for face in added {
            target = try appendFeatureShownByObject(
                .faceRebuild(FaceRebuildFeature(target: PatternTargetReference(featureID: target), faces: [face.reference], method: .given(face.surface))),
                name: "Raise Degree", object: nodeID, objectRegistry: objectRegistry
            )
        }
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
