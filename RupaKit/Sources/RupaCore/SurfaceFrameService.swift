import Foundation
import SwiftCAD

public struct SurfaceFrameService: Sendable {
    private let pipelineOverride: CADPipeline?
    private let tolerance: ModelingTolerance

    public init(
        pipeline: CADPipeline? = nil,
        tolerance: ModelingTolerance = .standard
    ) {
        self.pipelineOverride = pipeline
        self.tolerance = tolerance
    }

    private struct PersistentTopologyNames {
        var faceIDsByName: [String: FaceID]
        var faceNamesByID: [FaceID: [String]]
        var sourceFeatureIDsByFaceID: [FaceID: FeatureID]
    }

    public func resolve(
        document: DesignDocument,
        queries: [SurfaceFrameQuery],
        objectRegistry: ObjectTypeRegistry = .builtIn
    ) throws -> SurfaceFrameResult {
        do {
            try document.validate(objectRegistry: objectRegistry)
        } catch {
            throw EditorError(
                code: .evaluationFailed,
                message: "Document must validate before surface frame resolution: \(String(describing: error))"
            )
        }

        guard queries.isEmpty == false else {
            return SurfaceFrameResult(
                displayUnit: document.displayUnit,
                diagnostics: [
                    EditorDiagnostic(
                        severity: .info,
                        message: "Surface frame resolution completed with no requested UV frames."
                    ),
                ]
            )
        }

        let evaluatedDocument: EvaluatedDocument
        do {
            let pipeline = pipelineOverride ?? .modelingDefault(
                for: document,
                objectRegistry: objectRegistry
            )
            evaluatedDocument = try pipeline.evaluate(document.cadDocument)
        } catch {
            throw EditorError(
                code: .evaluationFailed,
                message: "Document must evaluate successfully before surface frame resolution: \(String(describing: error))"
            )
        }

        let persistentNames = persistentTopologyNames(in: evaluatedDocument)
        let sceneNodeIDsByFeatureID = sceneNodeIDsByFeatureID(in: document)
        let frames = try queries.map { query in
            try frame(
                for: query,
                evaluatedDocument: evaluatedDocument,
                persistentNames: persistentNames,
                sceneNodeIDsByFeatureID: sceneNodeIDsByFeatureID
            )
        }

        return SurfaceFrameResult(
            displayUnit: document.displayUnit,
            frames: frames,
            diagnostics: [
                EditorDiagnostic(
                    severity: .info,
                    message: "Surface frame resolution completed with \(frames.count) UV frame(s)."
                ),
            ]
        )
    }

    private func frame(
        for query: SurfaceFrameQuery,
        evaluatedDocument: EvaluatedDocument,
        persistentNames: PersistentTopologyNames,
        sceneNodeIDsByFeatureID: [FeatureID: SceneNodeID]
    ) throws -> SurfaceFrameResult.Frame {
        try validate(query)
        let faceID = try resolvedFaceID(for: query, persistentNames: persistentNames)
        guard let face = evaluatedDocument.brep.faces[faceID],
              let storedSurface = evaluatedDocument.brep.geometry.surfaces[face.surfaceID],
              case let .bSpline(surface) = storedSurface else {
            throw EditorError(
                code: .referenceUnresolved,
                message: "Surface frame resolution requires a generated B-spline face target."
            )
        }
        let uBounds = try parameterBounds(surface.uDomain)
        let vBounds = try parameterBounds(surface.vDomain)
        let geometry = try surface.differentialGeometry(atU: query.u, v: query.v, tolerance: tolerance)
        let orientationScale = face.orientation == .forward ? 1.0 : -1.0
        let orientedNormal = face.orientation == .forward ? geometry.normal : -geometry.normal
        let uAxis = try geometry.tangentU.normalized(tolerance: tolerance.distance)
        let vAxis = try orientedNormal.cross(uAxis).normalized(tolerance: tolerance.distance)
        let handedness = uAxis.cross(vAxis).dot(orientedNormal)
        let minimumPrincipalCurvature: Double
        let maximumPrincipalCurvature: Double
        let minimumPrincipalDirection: Vector3D
        let maximumPrincipalDirection: Vector3D
        if face.orientation == .forward {
            minimumPrincipalCurvature = geometry.minimumPrincipalCurvature
            maximumPrincipalCurvature = geometry.maximumPrincipalCurvature
            minimumPrincipalDirection = geometry.minimumPrincipalDirection
            maximumPrincipalDirection = geometry.maximumPrincipalDirection
        } else {
            minimumPrincipalCurvature = -geometry.maximumPrincipalCurvature
            maximumPrincipalCurvature = -geometry.minimumPrincipalCurvature
            minimumPrincipalDirection = geometry.maximumPrincipalDirection
            maximumPrincipalDirection = geometry.minimumPrincipalDirection
        }
        let sourceFeatureID = persistentNames.sourceFeatureIDsByFaceID[faceID]
        return SurfaceFrameResult.Frame(
            faceID: faceID.description,
            facePersistentNames: persistentNames.faceNamesByID[faceID] ?? [],
            sourceFeatureID: sourceFeatureID?.description,
            sceneNodeID: sourceFeatureID.flatMap { sceneNodeIDsByFeatureID[$0]?.description },
            u: query.u,
            v: query.v,
            uDomain: SurfaceAnalysisResult.ParameterRange(
                lowerBound: uBounds.lowerBound,
                upperBound: uBounds.upperBound
            ),
            vDomain: SurfaceAnalysisResult.ParameterRange(
                lowerBound: vBounds.lowerBound,
                upperBound: vBounds.upperBound
            ),
            position: point(geometry.position),
            tangentU: vector(geometry.tangentU),
            tangentV: vector(geometry.tangentV),
            uAxis: vector(uAxis),
            vAxis: vector(vAxis),
            normal: vector(orientedNormal),
            handedness: handedness,
            normalCurvatureU: geometry.normalCurvatureU * orientationScale,
            normalCurvatureV: geometry.normalCurvatureV * orientationScale,
            meanCurvature: geometry.meanCurvature * orientationScale,
            gaussianCurvature: geometry.gaussianCurvature,
            minimumPrincipalCurvature: minimumPrincipalCurvature,
            maximumPrincipalCurvature: maximumPrincipalCurvature,
            minimumPrincipalDirection: vector(minimumPrincipalDirection),
            maximumPrincipalDirection: vector(maximumPrincipalDirection)
        )
    }

    private func validate(_ query: SurfaceFrameQuery) throws {
        let hasFaceID = query.faceID.map { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty } ?? false
        let hasPersistentName = query.facePersistentName.map {
            !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        } ?? false
        guard hasFaceID != hasPersistentName else {
            throw EditorError(
                code: .referenceUnresolved,
                message: "Surface frame queries require exactly one faceID or facePersistentName."
            )
        }
        guard query.u.isFinite,
              query.v.isFinite else {
            throw EditorError(
                code: .commandInvalid,
                message: "Surface frame UV parameters must be finite."
            )
        }
    }

    private func resolvedFaceID(
        for query: SurfaceFrameQuery,
        persistentNames: PersistentTopologyNames
    ) throws -> FaceID {
        if let faceID = query.faceID {
            let trimmed = faceID.trimmingCharacters(in: .whitespacesAndNewlines)
            guard let uuid = UUID(uuidString: trimmed) else {
                throw EditorError(
                    code: .referenceUnresolved,
                    message: "Surface frame faceID must be a valid generated face UUID."
                )
            }
            return FaceID(uuid)
        }
        guard let facePersistentName = query.facePersistentName else {
            throw EditorError(
                code: .referenceUnresolved,
                message: "Surface frame query is missing a face target."
            )
        }
        let trimmed = facePersistentName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let faceID = persistentNames.faceIDsByName[trimmed] else {
            throw EditorError(
                code: .referenceUnresolved,
                message: "Surface frame facePersistentName did not resolve to a generated face."
            )
        }
        return faceID
    }

    private func parameterBounds(
        _ domain: ParameterDomain
    ) throws -> (lowerBound: Double, upperBound: Double) {
        try domain.validate(tolerance: tolerance)
        guard case let .closed(lowerBound, upperBound) = domain else {
            throw EditorError(
                code: .evaluationFailed,
                message: "B-spline surface frame resolution requires bounded parameter domains."
            )
        }
        return (lowerBound, upperBound)
    }

    private func persistentTopologyNames(
        in evaluatedDocument: EvaluatedDocument
    ) -> PersistentTopologyNames {
        var faceIDsByName: [String: FaceID] = [:]
        var faceNamesByID: [FaceID: [String]] = [:]
        var sourceFeatureIDsByFaceID: [FaceID: FeatureID] = [:]
        for (name, reference) in evaluatedDocument.generatedNames {
            guard case .face(let faceID) = reference else {
                continue
            }
            let stringName = persistentNameString(name)
            faceIDsByName[stringName] = faceID
            faceNamesByID[faceID, default: []].append(stringName)
            if sourceFeatureIDsByFaceID[faceID] == nil {
                sourceFeatureIDsByFaceID[faceID] = sourceFeatureID(in: name)
            }
        }
        for faceID in faceNamesByID.keys {
            faceNamesByID[faceID]?.sort()
        }
        return PersistentTopologyNames(
            faceIDsByName: faceIDsByName,
            faceNamesByID: faceNamesByID,
            sourceFeatureIDsByFaceID: sourceFeatureIDsByFaceID
        )
    }

    private func sceneNodeIDsByFeatureID(in document: DesignDocument) -> [FeatureID: SceneNodeID] {
        var mapping: [FeatureID: SceneNodeID] = [:]
        for (sceneNodeID, sceneNode) in document.productMetadata.sceneNodes {
            guard let featureID = sceneNode.reference?.featureID else {
                continue
            }
            mapping[featureID] = sceneNodeID
        }
        return mapping
    }

    private func sourceFeatureID(in name: PersistentName) -> FeatureID? {
        for component in name.components {
            guard case .feature(let featureID) = component else {
                continue
            }
            return featureID
        }
        return nil
    }

    private func persistentNameString(_ name: PersistentName) -> String {
        name.components.map { component in
            switch component {
            case .feature(let featureID):
                return "feature:\(featureID.description)"
            case .generated(let value):
                return "generated:\(value)"
            case .subshape(let value):
                return "subshape:\(value)"
            case .index(let index):
                return "index:\(index)"
            }
        }
        .joined(separator: "/")
    }

    private func point(_ point: Point3D) -> SurfaceAnalysisResult.Point {
        SurfaceAnalysisResult.Point(
            x: point.x,
            y: point.y,
            z: point.z
        )
    }

    private func vector(_ vector: Vector3D) -> SurfaceAnalysisResult.Vector {
        SurfaceAnalysisResult.Vector(
            x: vector.x,
            y: vector.y,
            z: vector.z
        )
    }
}
