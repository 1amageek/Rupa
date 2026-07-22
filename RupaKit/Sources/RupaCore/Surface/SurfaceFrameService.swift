import Foundation
import SwiftCAD
import RupaCoreTypes

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

    private struct ResolvedFrameTarget {
        var faceID: FaceID
        var explicitU: Double?
        var explicitV: Double?
        var controlPointIndex: ControlPointIndex?
    }

    private struct ControlPointIndex {
        var uIndex: Int
        var vIndex: Int
    }

    public func resolve(
        document: DesignDocument,
        queries: [SurfaceFrameQuery],
        displayUnit: LengthDisplayUnit,
        objectRegistry: ObjectTypeRegistry = .builtIn,
        currentEvaluation: DocumentEvaluationContext? = nil,
        currentGeneration: DocumentGeneration? = nil
    ) throws -> SurfaceFrameResult {
        let frames = try resolveFrames(
            document: document,
            queries: queries,
            objectRegistry: objectRegistry,
            currentEvaluation: currentEvaluation,
            currentGeneration: currentGeneration
        )
        let message = frames.isEmpty
            ? "Surface frame resolution completed with no requested UV frames."
            : "Surface frame resolution completed with \(frames.count) UV frame(s)."
        return SurfaceFrameResult(
            displayUnit: displayUnit,
            frames: frames,
            diagnostics: [
                EditorDiagnostic(
                    severity: .info,
                    message: message
                ),
            ]
        )
    }

    public func resolveFrames(
        document: DesignDocument,
        queries: [SurfaceFrameQuery],
        objectRegistry: ObjectTypeRegistry = .builtIn,
        currentEvaluation: DocumentEvaluationContext? = nil,
        currentGeneration: DocumentGeneration? = nil
    ) throws -> [SurfaceFrameResult.Frame] {
        do {
            try document.validate(objectRegistry: objectRegistry)
        } catch {
            throw EditorError(
                code: .evaluationFailed,
                message: "Document must validate before surface frame resolution: \(String(describing: error))"
            )
        }

        guard queries.isEmpty == false else {
            return []
        }

        let evaluatedDocument = try DocumentEvaluationContextResolver(
            pipeline: pipelineOverride
        ).evaluatedDocument(
            document: document,
            objectRegistry: objectRegistry,
            currentEvaluation: currentEvaluation,
            currentGeneration: currentGeneration,
            failurePrefix: "Document must evaluate successfully before surface frame resolution"
        )

        let persistentNames = try persistentTopologyNames(in: evaluatedDocument)
        let sceneNodeIDsByFeatureID = sceneNodeIDsByFeatureID(in: document)
        return try queries.map { query in
            try frame(
                for: query,
                evaluatedDocument: evaluatedDocument,
                persistentNames: persistentNames,
                sceneNodeIDsByFeatureID: sceneNodeIDsByFeatureID
            )
        }

    }

    private func frame(
        for query: SurfaceFrameQuery,
        evaluatedDocument: EvaluatedDocument,
        persistentNames: PersistentTopologyNames,
        sceneNodeIDsByFeatureID: [FeatureID: SceneNodeID]
    ) throws -> SurfaceFrameResult.Frame {
        try validate(query)
        let target = try resolvedTarget(
            for: query,
            evaluatedDocument: evaluatedDocument,
            persistentNames: persistentNames
        )
        guard let face = evaluatedDocument.brep.faces[target.faceID],
              let storedSurface = evaluatedDocument.brep.geometry.surfaces[face.surfaceID],
              case let .bSpline(surface) = storedSurface else {
            throw EditorError(
                code: .referenceUnresolved,
                message: "Surface frame resolution requires a generated B-spline face target."
            )
        }
        let uBounds = try parameterBounds(surface.uDomain)
        let vBounds = try parameterBounds(surface.vDomain)
        let parameter = try resolvedParameter(target, surface: surface)
        let geometry = try surface.differentialGeometry(atU: parameter.u, v: parameter.v, tolerance: tolerance)
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
        let sourceFeatureID = persistentNames.sourceFeatureIDsByFaceID[target.faceID]
        return SurfaceFrameResult.Frame(
            faceID: target.faceID.description,
            facePersistentNames: persistentNames.faceNamesByID[target.faceID] ?? [],
            sourceFeatureID: sourceFeatureID?.description,
            sceneNodeID: sourceFeatureID.flatMap { sceneNodeIDsByFeatureID[$0]?.description },
            u: parameter.u,
            v: parameter.v,
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
        let hasStableReference = query.faceStableReference != nil
        let hasSelectionReference = query.selectionReference != nil
        guard [hasFaceID, hasStableReference, hasSelectionReference].filter({ $0 }).count == 1 else {
            throw EditorError(
                code: .referenceUnresolved,
                message: "Surface frame queries require exactly one faceID, faceStableReference, or selectionReference."
            )
        }
        if let selectionReference = query.selectionReference {
            do {
                try selectionReference.validate()
            } catch {
                throw EditorError(
                    code: .commandInvalid,
                    message: "Surface frame selectionReference is invalid: \(String(describing: error))."
                )
            }
            try validateSelectionReferenceMode(selectionReference, query: query)
        } else {
            try validateExplicitUV(query)
        }
    }

    private func validateExplicitUV(_ query: SurfaceFrameQuery) throws {
        guard let u = query.u,
              let v = query.v else {
            throw EditorError(
                code: .commandInvalid,
                message: "Surface frame faceID or faceStableReference queries require both u and v parameters."
            )
        }
        guard u.isFinite,
              v.isFinite else {
            throw EditorError(
                code: .commandInvalid,
                message: "Surface frame UV parameters must be finite."
            )
        }
    }

    private func validateSelectionReferenceMode(
        _ selectionReference: SelectionReference,
        query: SurfaceFrameQuery
    ) throws {
        switch selectionReference {
        case .subshape:
            try validateExplicitUV(query)
        case .surface(.whole):
            try validateExplicitUV(query)
        case .surface(.parameter),
             .surface(.controlPoint),
             .surface(.trimSpan),
             .surface(.trimKnot):
            guard query.u == nil,
                  query.v == nil else {
                throw EditorError(
                    code: .commandInvalid,
                    message: "Surface frame parameter, control-point, and trim p-curve selectionReference queries carry their own UV address and must not also provide u or v."
                )
            }
        case .surface(.span),
             .surface(.knot),
             .surface(.trim),
             .edge,
             .curve,
             .sketchPoint:
            throw EditorError(
                code: .commandInvalid,
                message: "Surface frame selectionReference must target a generated face, surface parameter, surface control point, or trim p-curve parameter."
            )
        }
    }

    private func resolvedTarget(
        for query: SurfaceFrameQuery,
        evaluatedDocument: EvaluatedDocument,
        persistentNames: PersistentTopologyNames
    ) throws -> ResolvedFrameTarget {
        if let faceID = query.faceID {
            let trimmed = faceID.trimmingCharacters(in: .whitespacesAndNewlines)
            guard let uuid = UUID(uuidString: trimmed) else {
                throw EditorError(
                    code: .referenceUnresolved,
                    message: "Surface frame faceID must be a valid generated face UUID."
                )
            }
            return ResolvedFrameTarget(
                faceID: FaceID(uuid),
                explicitU: query.u,
                explicitV: query.v
            )
        }
        if let faceStableReference = query.faceStableReference {
            return ResolvedFrameTarget(
                faceID: try resolvedFaceID(
                    for: faceStableReference,
                    in: evaluatedDocument
                ),
                explicitU: query.u,
                explicitV: query.v
            )
        }
        guard let selectionReference = query.selectionReference else {
            throw EditorError(
                code: .referenceUnresolved,
                message: "Surface frame query is missing a face target."
            )
        }
        return try resolvedTarget(
            forSelectionReference: selectionReference,
            query: query,
            evaluatedDocument: evaluatedDocument,
            persistentNames: persistentNames
        )
    }

    private func resolvedTarget(
        forSelectionReference selectionReference: SelectionReference,
        query: SurfaceFrameQuery,
        evaluatedDocument: EvaluatedDocument,
        persistentNames: PersistentTopologyNames
    ) throws -> ResolvedFrameTarget {
        switch selectionReference {
        case .subshape(let reference):
            return ResolvedFrameTarget(
                faceID: try resolvedFaceID(
                    for: reference,
                    in: evaluatedDocument
                ),
                explicitU: query.u,
                explicitV: query.v
            )
        case .surface(.whole(let reference)):
            return ResolvedFrameTarget(
                faceID: try resolvedFaceID(
                    for: reference.subshape,
                    in: evaluatedDocument
                ),
                explicitU: query.u,
                explicitV: query.v
            )
        case .surface(.parameter(let reference)):
            return ResolvedFrameTarget(
                faceID: try resolvedFaceID(
                    for: reference.surface.subshape,
                    in: evaluatedDocument
                ),
                explicitU: reference.u,
                explicitV: reference.v
            )
        case .surface(.controlPoint(let reference)):
            return ResolvedFrameTarget(
                faceID: try resolvedFaceID(
                    for: reference.surface.subshape,
                    in: evaluatedDocument
                ),
                controlPointIndex: ControlPointIndex(
                    uIndex: reference.uIndex,
                    vIndex: reference.vIndex
                )
            )
        case .surface(.trimSpan(let reference)):
            let parameter = try resolvedTrimSpanParameter(
                reference,
                evaluatedDocument: evaluatedDocument
            )
            return ResolvedFrameTarget(
                faceID: try resolvedFaceID(
                    for: reference.trim.surface.subshape,
                    in: evaluatedDocument
                ),
                explicitU: parameter.u,
                explicitV: parameter.v
            )
        case .surface(.trimKnot(let reference)):
            let parameter = try resolvedTrimKnotParameter(
                reference,
                evaluatedDocument: evaluatedDocument
            )
            return ResolvedFrameTarget(
                faceID: try resolvedFaceID(
                    for: reference.trim.surface.subshape,
                    in: evaluatedDocument
                ),
                explicitU: parameter.u,
                explicitV: parameter.v
            )
        case .surface(.span),
             .surface(.knot),
             .surface(.trim),
             .edge,
             .curve,
             .sketchPoint:
            throw EditorError(
                code: .commandInvalid,
                message: "Surface frame selectionReference must target a generated face, surface parameter, surface control point, or trim p-curve parameter."
            )
        }
    }

    private func resolvedTrimSpanParameter(
        _ reference: SurfaceTrimSpanReference,
        evaluatedDocument: EvaluatedDocument
    ) throws -> SurfaceParameter {
        let trim = try SurfaceQueryEvaluator(tolerance: tolerance).trimCurve(reference.trim, in: evaluatedDocument)
        guard case let .bSpline(curve) = trim.parameterCurve else {
            throw EditorError(
                code: .commandInvalid,
                message: "Surface frame trim span selection requires a B-spline p-curve."
            )
        }
        let curveParameter = try trimSpanParameter(reference.spanIndex, on: curve)
        let point = try curve.point(at: curveParameter, tolerance: tolerance)
        return SurfaceParameter(u: point.x, v: point.y)
    }

    private func resolvedTrimKnotParameter(
        _ reference: SurfaceTrimKnotReference,
        evaluatedDocument: EvaluatedDocument
    ) throws -> SurfaceParameter {
        let trim = try SurfaceQueryEvaluator(tolerance: tolerance).trimCurve(reference.trim, in: evaluatedDocument)
        guard case let .bSpline(curve) = trim.parameterCurve else {
            throw EditorError(
                code: .commandInvalid,
                message: "Surface frame trim knot selection requires a B-spline p-curve."
            )
        }
        guard curve.knots.indices.contains(reference.knotIndex) else {
            throw EditorError(
                code: .referenceUnresolved,
                message: "Surface frame trim knot selection references a missing p-curve knot."
            )
        }
        let curveParameter = curve.knots[reference.knotIndex]
        guard try curve.domain.contains(curveParameter, tolerance: tolerance) else {
            throw EditorError(
                code: .referenceUnresolved,
                message: "Surface frame trim knot selection is outside the p-curve domain."
            )
        }
        let point = try curve.point(at: curveParameter, tolerance: tolerance)
        return SurfaceParameter(u: point.x, v: point.y)
    }

    private func trimSpanParameter(_ spanIndex: Int, on curve: BSplineCurve2D) throws -> Double {
        try curve.validate(tolerance: tolerance)
        let lowerIndex = curve.degree
        let upperIndex = curve.knots.count - curve.degree - 1
        guard lowerIndex < upperIndex else {
            throw EditorError(
                code: .referenceUnresolved,
                message: "Surface frame trim span selection found no queryable p-curve spans."
            )
        }
        var ordinal = 0
        for knotIndex in lowerIndex..<upperIndex {
            let lower = curve.knots[knotIndex]
            let upper = curve.knots[knotIndex + 1]
            guard upper - lower > tolerance.distance else {
                continue
            }
            if ordinal == spanIndex {
                return (lower + upper) * 0.5
            }
            ordinal += 1
        }
        throw EditorError(
            code: .referenceUnresolved,
            message: "Surface frame trim span selection references a missing p-curve span."
        )
    }

    private func resolvedFaceID(
        for reference: StableSubshapeReference,
        in evaluatedDocument: EvaluatedDocument
    ) throws -> FaceID {
        guard case .face(let faceID) = try evaluatedDocument.topologyReference(
            for: reference
        ) else {
            throw EditorError(
                code: .referenceUnresolved,
                message: "Surface frame stable reference did not resolve to a generated face."
            )
        }
        return faceID
    }

    private func resolvedParameter(
        _ target: ResolvedFrameTarget,
        surface: BSplineSurface3D
    ) throws -> (u: Double, v: Double) {
        if let controlPointIndex = target.controlPointIndex {
            return (
                u: try grevilleParameter(
                    controlPointIndex.uIndex,
                    degree: surface.uDegree,
                    knots: surface.uKnots,
                    controlPointCount: surface.uControlPointCount,
                    direction: "U"
                ),
                v: try grevilleParameter(
                    controlPointIndex.vIndex,
                    degree: surface.vDegree,
                    knots: surface.vKnots,
                    controlPointCount: surface.vControlPointCount,
                    direction: "V"
                )
            )
        }
        guard let u = target.explicitU,
              let v = target.explicitV else {
            throw EditorError(
                code: .commandInvalid,
                message: "Surface frame query requires resolved finite UV parameters."
            )
        }
        return (u, v)
    }

    private func grevilleParameter(
        _ controlPointIndex: Int,
        degree: Int,
        knots: [Double],
        controlPointCount: Int,
        direction: String
    ) throws -> Double {
        guard (0 ..< controlPointCount).contains(controlPointIndex) else {
            throw EditorError(
                code: .referenceUnresolved,
                message: "Surface frame \(direction) control point index is outside the generated B-spline control net."
            )
        }
        guard degree > 0 else {
            throw EditorError(
                code: .commandInvalid,
                message: "Surface frame control-point queries require a positive B-spline degree."
            )
        }
        guard controlPointIndex + degree < knots.count else {
            throw EditorError(
                code: .referenceUnresolved,
                message: "Surface frame \(direction) control point index cannot resolve a Greville parameter from the knot vector."
            )
        }
        var sum = 0.0
        for knotIndex in (controlPointIndex + 1)...(controlPointIndex + degree) {
            let knot = knots[knotIndex]
            guard knot.isFinite else {
                throw EditorError(
                    code: .commandInvalid,
                    message: "Surface frame \(direction) knot vector contains a non-finite value."
                )
            }
            sum += knot
        }
        return sum / Double(degree)
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
    ) throws -> PersistentTopologyNames {
        var faceIDsByName: [String: FaceID] = [:]
        var faceNamesByID: [FaceID: [String]] = [:]
        var sourceFeatureIDsByFaceID: [FaceID: FeatureID] = [:]
        for (subshapeID, reference) in evaluatedDocument.subshapes.entries {
            guard case .face(let faceID) = reference else {
                continue
            }
            let stringName = stableSubshapeKey(
                try evaluatedDocument.stableSubshapeReference(for: subshapeID)
            )
            faceIDsByName[stringName] = faceID
            faceNamesByID[faceID, default: []].append(stringName)
            if sourceFeatureIDsByFaceID[faceID] == nil {
                sourceFeatureIDsByFaceID[faceID] = subshapeID.featureID
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

    private func stableSubshapeKey(_ reference: StableSubshapeReference) -> String {
        let id = reference.subshapeID
        return "feature:\(id.featureID.description)/role:\(id.role)/ordinal:\(id.ordinal)"
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
