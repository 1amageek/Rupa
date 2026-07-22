import Foundation
import SwiftCAD
import CADTopology
import RupaCoreTypes

public struct SurfaceAnalysisService: Sendable {
    private let pipelineOverride: CADPipeline?
    private let tolerance: ModelingTolerance
    private let options: SurfaceAnalysisOptions

    public init(
        pipeline: CADPipeline? = nil,
        tolerance: ModelingTolerance = .standard,
        options: SurfaceAnalysisOptions = SurfaceAnalysisOptions()
    ) {
        self.pipelineOverride = pipeline
        self.tolerance = tolerance
        self.options = options
    }

    private struct PersistentTopologyNames {
        var faceNamesByID: [FaceID: [String]]
        var edgeNamesByID: [EdgeID: [String]]
        var sourceFeatureIDsByFaceID: [FaceID: FeatureID]
    }

    private struct SurfaceSampleState {
        var sample: SurfaceAnalysisResult.Sample
        var position: Point3D
        var normal: Vector3D
        var normalCurvatureU: Double
        var normalCurvatureV: Double
    }

    public func analyze(
        document: DesignDocument,
        displayUnit: LengthDisplayUnit,
        objectRegistry: ObjectTypeRegistry = .builtIn,
        currentEvaluation: DocumentEvaluationContext? = nil,
        currentGeneration: DocumentGeneration? = nil
    ) throws -> SurfaceAnalysisResult {
        do {
            try document.validate(objectRegistry: objectRegistry)
        } catch {
            throw EditorError(
                code: .evaluationFailed,
                message: "Document must validate before surface analysis: \(String(describing: error))"
            )
        }

        guard document.cadDocument.hasActiveRenderableTopologyFeatures else {
            return SurfaceAnalysisResult(
                displayUnit: displayUnit,
                diagnostics: [
                    EditorDiagnostic(
                        severity: .info,
                        message: "Document source is valid. No generated surface topology."
                    ),
                ]
            )
        }

        let evaluatedDocument = try DocumentEvaluationContextResolver(
            pipeline: pipelineOverride
        ).evaluatedDocument(
            document: document,
            objectRegistry: objectRegistry,
            currentEvaluation: currentEvaluation,
            currentGeneration: currentGeneration,
            failurePrefix: "Document must evaluate successfully before surface analysis"
        )

        let persistentNames = persistentTopologyNames(in: evaluatedDocument)
        let sceneNodeIDsByFeatureID = sceneNodeIDsByFeatureID(in: document)
        var skippedDegenerateCombCount = 0
        var faces: [SurfaceAnalysisResult.FaceAnalysis] = []
        faces.reserveCapacity(evaluatedDocument.brep.faces.count)

        for faceID in evaluatedDocument.brep.faces.keys.sorted(by: { $0.description < $1.description }) {
            guard let face = evaluatedDocument.brep.faces[faceID],
                  let storedSurface = evaluatedDocument.brep.geometry.surfaces[face.surfaceID],
                  case let .bSpline(surface) = storedSurface else {
                continue
            }
            faces.append(
                try faceAnalysis(
                    faceID: faceID,
                    face: face,
                    surface: surface,
                    model: evaluatedDocument.brep,
                    persistentNames: persistentNames,
                    sceneNodeIDsByFeatureID: sceneNodeIDsByFeatureID,
                    skippedDegenerateCombCount: &skippedDegenerateCombCount
                )
            )
        }

        return SurfaceAnalysisResult(
            displayUnit: displayUnit,
            counts: counts(for: faces),
            faces: faces.sorted { lhs, rhs in
                let lhsName = lhs.facePersistentNames.first ?? lhs.faceID
                let rhsName = rhs.facePersistentNames.first ?? rhs.faceID
                return lhsName < rhsName
            },
            diagnostics: diagnostics(
                faceCount: faces.count,
                sampleCount: faces.reduce(0) { $0 + $1.samples.count },
                skippedDegenerateCombCount: skippedDegenerateCombCount,
                openTrimBoundaryCount: faces.reduce(0) { partial, face in
                    partial + face.trimBoundaries.filter { !$0.isClosed }.count
                }
            )
        )
    }

    private func faceAnalysis(
        faceID: FaceID,
        face: Face,
        surface: BSplineSurface3D,
        model: BRepModel,
        persistentNames: PersistentTopologyNames,
        sceneNodeIDsByFeatureID: [FeatureID: SceneNodeID],
        skippedDegenerateCombCount: inout Int
    ) throws -> SurfaceAnalysisResult.FaceAnalysis {
        let uBounds = try parameterBounds(surface.uDomain)
        let vBounds = try parameterBounds(surface.vDomain)
        let uParameters = parameterSamples(lowerBound: uBounds.lowerBound, upperBound: uBounds.upperBound)
        let vParameters = parameterSamples(lowerBound: vBounds.lowerBound, upperBound: vBounds.upperBound)
        var grid: [[SurfaceSampleState]] = []
        var samples: [SurfaceAnalysisResult.Sample] = []
        let expectedSampleCount = uParameters.count * vParameters.count
        grid.reserveCapacity(vParameters.count)
        samples.reserveCapacity(expectedSampleCount)

        for v in vParameters {
            var row: [SurfaceSampleState] = []
            row.reserveCapacity(uParameters.count)
            for u in uParameters {
                let geometry = try surface.differentialGeometry(atU: u, v: v, tolerance: tolerance)
                let orientationScale = face.orientation == .forward ? 1.0 : -1.0
                let position = geometry.position
                let normal = face.orientation == .forward ? geometry.normal : -geometry.normal
                let normalCurvatureU = geometry.normalCurvatureU * orientationScale
                let normalCurvatureV = geometry.normalCurvatureV * orientationScale
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
                let sample = SurfaceAnalysisResult.Sample(
                    u: u,
                    v: v,
                    position: point(position),
                    normal: vector(normal),
                    tangentU: vector(geometry.tangentU),
                    tangentV: vector(geometry.tangentV),
                    normalCurvatureU: normalCurvatureU,
                    normalCurvatureV: normalCurvatureV,
                    meanCurvature: geometry.meanCurvature * orientationScale,
                    gaussianCurvature: geometry.gaussianCurvature,
                    minimumPrincipalCurvature: minimumPrincipalCurvature,
                    maximumPrincipalCurvature: maximumPrincipalCurvature,
                    minimumPrincipalDirection: vector(minimumPrincipalDirection),
                    maximumPrincipalDirection: vector(maximumPrincipalDirection)
                )
                row.append(
                    SurfaceSampleState(
                        sample: sample,
                        position: position,
                        normal: normal,
                        normalCurvatureU: normalCurvatureU,
                        normalCurvatureV: normalCurvatureV
                    )
                )
                samples.append(sample)
            }
            grid.append(row)
        }

        var curvatureCombs: [SurfaceAnalysisResult.CurvatureCombSample] = []
        curvatureCombs.reserveCapacity(expectedSampleCount * 2)
        for vIndex in vParameters.indices {
            for uIndex in uParameters.indices {
                if let comb = curvatureCombSample(
                    direction: .u,
                    uIndex: uIndex,
                    vIndex: vIndex,
                    grid: grid
                ) {
                    curvatureCombs.append(comb)
                } else {
                    skippedDegenerateCombCount += 1
                }
                if let comb = curvatureCombSample(
                    direction: .v,
                    uIndex: uIndex,
                    vIndex: vIndex,
                    grid: grid
                ) {
                    curvatureCombs.append(comb)
                } else {
                    skippedDegenerateCombCount += 1
                }
            }
        }

        let uCombs = curvatureCombs.filter { $0.direction == .u }
        let vCombs = curvatureCombs.filter { $0.direction == .v }
        let sourceFeatureID = persistentNames.sourceFeatureIDsByFaceID[faceID]
        let trimBoundaries = try trimBoundaries(
            for: face,
            in: model,
            persistentNames: persistentNames
        )

        return SurfaceAnalysisResult.FaceAnalysis(
            faceID: faceID.description,
            facePersistentNames: persistentNames.faceNamesByID[faceID] ?? [],
            edgePersistentNames: edgePersistentNames(
                for: face,
                in: model,
                persistentNames: persistentNames
            ),
            trimBoundaries: trimBoundaries,
            sourceFeatureID: sourceFeatureID?.description,
            sceneNodeID: sourceFeatureID.flatMap { sceneNodeIDsByFeatureID[$0]?.description },
            uDegree: surface.uDegree,
            vDegree: surface.vDegree,
            uControlPointCount: surface.uControlPointCount,
            vControlPointCount: surface.vControlPointCount,
            uDomain: SurfaceAnalysisResult.ParameterRange(
                lowerBound: uBounds.lowerBound,
                upperBound: uBounds.upperBound
            ),
            vDomain: SurfaceAnalysisResult.ParameterRange(
                lowerBound: vBounds.lowerBound,
                upperBound: vBounds.upperBound
            ),
            samples: samples,
            curvatureCombs: curvatureCombs,
            maxUNormalChangePerLength: uCombs.map(\.normalChangePerLength).max() ?? 0.0,
            maxVNormalChangePerLength: vCombs.map(\.normalChangePerLength).max() ?? 0.0,
            maxNormalAngle: curvatureCombs.map(\.normalAngle).max() ?? 0.0,
            maxAbsUNormalCurvature: maxAbs(samples.map(\.normalCurvatureU)),
            maxAbsVNormalCurvature: maxAbs(samples.map(\.normalCurvatureV)),
            maxAbsPrincipalCurvature: maxAbs(
                samples.flatMap {
                    [$0.minimumPrincipalCurvature, $0.maximumPrincipalCurvature]
                }
            ),
            maxAbsGaussianCurvature: maxAbs(samples.map(\.gaussianCurvature))
        )
    }

    private func curvatureCombSample(
        direction: SurfaceAnalysisResult.Direction,
        uIndex: Int,
        vIndex: Int,
        grid: [[SurfaceSampleState]]
    ) -> SurfaceAnalysisResult.CurvatureCombSample? {
        let center = grid[vIndex][uIndex]
        let previous: SurfaceSampleState
        let next: SurfaceSampleState
        switch direction {
        case .u:
            previous = grid[vIndex][max(uIndex - 1, 0)]
            next = grid[vIndex][min(uIndex + 1, grid[vIndex].count - 1)]
        case .v:
            previous = grid[max(vIndex - 1, 0)][uIndex]
            next = grid[min(vIndex + 1, grid.count - 1)][uIndex]
        }
        let distance = (next.position - previous.position).length
        guard distance > tolerance.distance else {
            return nil
        }
        let normalAngle = angle(between: previous.normal, and: next.normal)
        return SurfaceAnalysisResult.CurvatureCombSample(
            direction: direction,
            u: center.sample.u,
            v: center.sample.v,
            position: center.sample.position,
            normal: center.sample.normal,
            neighborDistance: distance,
            normalAngle: normalAngle,
            normalChangePerLength: normalAngle / distance,
            normalCurvature: direction == .u ? center.normalCurvatureU : center.normalCurvatureV
        )
    }

    private func parameterSamples(lowerBound: Double, upperBound: Double) -> [Double] {
        let samplesPerDirection = options.samplesPerDirection
        guard samplesPerDirection > 1 else {
            return [lowerBound]
        }
        let step = (upperBound - lowerBound) / Double(samplesPerDirection - 1)
        return (0..<samplesPerDirection).map { index in
            lowerBound + step * Double(index)
        }
    }

    private func parameterBounds(
        _ domain: ParameterDomain
    ) throws -> (lowerBound: Double, upperBound: Double) {
        try domain.validate(tolerance: tolerance)
        guard case let .closed(lowerBound, upperBound) = domain else {
            throw EditorError(
                code: .evaluationFailed,
                message: "B-spline surface analysis requires bounded parameter domains."
            )
        }
        return (lowerBound, upperBound)
    }

    private func trimBoundaries(
        for face: Face,
        in model: BRepModel,
        persistentNames: PersistentTopologyNames
    ) throws -> [SurfaceAnalysisResult.TrimBoundary] {
        var result: [SurfaceAnalysisResult.TrimBoundary] = []
        result.reserveCapacity(face.loops.count)
        for loopID in face.loops {
            guard let loop = model.loops[loopID] else {
                throw EditorError(
                    code: .evaluationFailed,
                    message: "Surface analysis encountered a missing B-rep loop."
                )
            }
            let orderedVertexIDs = try model.orderedVertexIDs(for: loopID)
            let points = try points(for: orderedVertexIDs, in: model)
            let edgeNames = Set(
                loop.edges.flatMap { orientedEdge in
                    persistentNames.edgeNamesByID[orientedEdge.edgeID] ?? []
                }
            )
            let length = try loop.edges.reduce(0.0) { partial, orientedEdge in
                partial + (try estimatedLength(for: orientedEdge, in: model))
            }
            result.append(
                SurfaceAnalysisResult.TrimBoundary(
                    loopID: loopID.description,
                    role: trimBoundaryRole(loop.role),
                    points: points,
                    edgePersistentNames: edgeNames.sorted(),
                    edgeCount: loop.edges.count,
                    vertexCount: orderedVertexIDs.count,
                    isClosed: try isClosed(loop: loop, orderedVertexIDs: orderedVertexIDs, in: model),
                    estimatedLength: length
                )
            )
        }
        return result
    }

    private func points(
        for vertexIDs: [VertexID],
        in model: BRepModel
    ) throws -> [SurfaceAnalysisResult.Point] {
        try vertexIDs.map { vertexID in
            guard let vertex = model.vertices[vertexID] else {
                throw EditorError(
                    code: .evaluationFailed,
                    message: "Surface analysis encountered a trim boundary with a missing vertex."
                )
            }
            return point(vertex.point)
        }
    }

    private func isClosed(
        loop: Loop,
        orderedVertexIDs: [VertexID],
        in model: BRepModel
    ) throws -> Bool {
        guard let firstVertexID = orderedVertexIDs.first,
              let lastOrientedEdge = loop.edges.last else {
            return false
        }
        let lastVertexID = try orientedVertexIDs(for: lastOrientedEdge, in: model).end
        if firstVertexID == lastVertexID {
            return true
        }
        guard let firstPoint = model.vertices[firstVertexID]?.point,
              let lastPoint = model.vertices[lastVertexID]?.point else {
            throw EditorError(
                code: .evaluationFailed,
                message: "Surface analysis encountered a trim boundary with missing vertices."
            )
        }
        return firstPoint.isApproximatelyEqual(to: lastPoint, tolerance: tolerance.distance)
    }

    private func estimatedLength(
        for orientedEdge: Coedge,
        in model: BRepModel
    ) throws -> Double {
        let vertexIDs = try orientedVertexIDs(for: orientedEdge, in: model)
        guard let edge = model.edges[orientedEdge.edgeID],
              let start = model.vertices[vertexIDs.start]?.point,
              let end = model.vertices[vertexIDs.end]?.point,
              let curve = model.geometry.curves[edge.curveID] else {
            throw EditorError(
                code: .evaluationFailed,
                message: "Surface analysis encountered missing trim boundary edge geometry."
            )
        }
        let chordLength = (end - start).length
        switch curve {
        case .line:
            return chordLength
        case .circle(let circle):
            guard let trim = edge.trim else {
                return chordLength
            }
            return abs(trim.endParameter - trim.startParameter) * circle.radius
        case .analytic,
             .bSpline,
             .implicit,
             .surfaceLift:
            return try estimatedSampledLength(
                for: curve,
                edge: edge,
                fallback: chordLength
            )
        }
    }

    private func estimatedSampledLength(
        for curve: Curve3D,
        edge: Edge,
        fallback: Double
    ) throws -> Double {
        let parameterSpan: (start: Double, end: Double)
        if let trim = edge.trim {
            parameterSpan = (trim.startParameter, trim.endParameter)
        } else {
            switch curve.parameterDomain {
            case .unbounded:
                return fallback
            case .closed(let start, let end):
                parameterSpan = (start, end)
            case .periodic(let period):
                parameterSpan = (0.0, period)
            }
        }

        guard parameterSpan.start.isFinite,
              parameterSpan.end.isFinite else {
            return fallback
        }
        let span = parameterSpan.end - parameterSpan.start
        guard abs(span) > tolerance.distance else {
            return fallback
        }

        let segmentCount = 32
        do {
            var previous = try curve.point(at: parameterSpan.start, tolerance: tolerance)
            var length = 0.0
            for index in 1...segmentCount {
                let parameter = parameterSpan.start + span * Double(index) / Double(segmentCount)
                let current = try curve.point(at: parameter, tolerance: tolerance)
                length += (current - previous).length
                previous = current
            }
            return length
        } catch {
            throw EditorError(
                code: .evaluationFailed,
                message: "Surface analysis could not sample trim boundary curve length: \(String(describing: error))"
            )
        }
    }

    private func orientedVertexIDs(
        for orientedEdge: Coedge,
        in model: BRepModel
    ) throws -> (start: VertexID, end: VertexID) {
        guard let edge = model.edges[orientedEdge.edgeID] else {
            throw EditorError(
                code: .evaluationFailed,
                message: "Surface analysis encountered a missing B-rep edge."
            )
        }
        switch orientedEdge.orientation {
        case .forward:
            return (edge.startVertexID, edge.endVertexID)
        case .reversed:
            return (edge.endVertexID, edge.startVertexID)
        }
    }

    private func trimBoundaryRole(_ role: LoopRole) -> SurfaceAnalysisResult.TrimBoundaryRole {
        switch role {
        case .outer:
            return .outer
        case .inner:
            return .inner
        }
    }

    private func edgePersistentNames(
        for face: Face,
        in model: BRepModel,
        persistentNames: PersistentTopologyNames
    ) -> [String] {
        var result = Set<String>()
        for loopID in face.loops {
            guard let loop = model.loops[loopID] else {
                continue
            }
            for orientedEdge in loop.edges {
                result.formUnion(persistentNames.edgeNamesByID[orientedEdge.edgeID] ?? [])
            }
        }
        return result.sorted()
    }

    private func counts(
        for faces: [SurfaceAnalysisResult.FaceAnalysis]
    ) -> SurfaceAnalysisResult.Counts {
        SurfaceAnalysisResult.Counts(
            bSplineFaceCount: faces.count,
            sampleCount: faces.reduce(0) { $0 + $1.samples.count },
            uCurvatureCombCount: faces.reduce(0) { partial, face in
                partial + face.curvatureCombs.filter { $0.direction == .u }.count
            },
            vCurvatureCombCount: faces.reduce(0) { partial, face in
                partial + face.curvatureCombs.filter { $0.direction == .v }.count
            },
            trimBoundaryCount: faces.reduce(0) { partial, face in
                partial + face.trimBoundaries.count
            },
            innerTrimBoundaryCount: faces.reduce(0) { partial, face in
                partial + face.trimBoundaries.filter { $0.role == .inner }.count
            },
            openTrimBoundaryCount: faces.reduce(0) { partial, face in
                partial + face.trimBoundaries.filter { !$0.isClosed }.count
            },
            trimBoundaryEdgeCount: faces.reduce(0) { partial, face in
                partial + face.trimBoundaries.reduce(0) { boundaryPartial, boundary in
                    boundaryPartial + boundary.edgeCount
                }
            }
        )
    }

    private func diagnostics(
        faceCount: Int,
        sampleCount: Int,
        skippedDegenerateCombCount: Int,
        openTrimBoundaryCount: Int
    ) -> [EditorDiagnostic] {
        var result = [
            EditorDiagnostic(
                severity: .info,
                message: "Surface analysis completed with \(faceCount) B-spline face(s) and \(sampleCount) UV sample(s)."
            ),
        ]
        if skippedDegenerateCombCount > 0 {
            result.append(
                EditorDiagnostic(
                    severity: .warning,
                    message: "\(skippedDegenerateCombCount) surface curvature comb sample(s) were skipped because adjacent UV samples were degenerate."
                )
            )
        }
        if openTrimBoundaryCount > 0 {
            result.append(
                EditorDiagnostic(
                    severity: .warning,
                    message: "\(openTrimBoundaryCount) trim boundary loop(s) were reported as open."
                )
            )
        }
        return result
    }

    private func persistentTopologyNames(
        in evaluatedDocument: EvaluatedDocument
    ) -> PersistentTopologyNames {
        var faceNamesByID: [FaceID: [String]] = [:]
        var edgeNamesByID: [EdgeID: [String]] = [:]
        var sourceFeatureIDsByFaceID: [FaceID: FeatureID] = [:]
        for (subshapeID, reference) in evaluatedDocument.subshapes.entries {
            let stringName = stableSubshapeKey(subshapeID)
            switch reference {
            case .body, .vertex:
                continue
            case .face(let faceID):
                faceNamesByID[faceID, default: []].append(stringName)
                if sourceFeatureIDsByFaceID[faceID] == nil {
                    sourceFeatureIDsByFaceID[faceID] = subshapeID.featureID
                }
            case .edge(let edgeID):
                edgeNamesByID[edgeID, default: []].append(stringName)
            }
        }
        for faceID in faceNamesByID.keys {
            faceNamesByID[faceID]?.sort()
        }
        for edgeID in edgeNamesByID.keys {
            edgeNamesByID[edgeID]?.sort()
        }
        return PersistentTopologyNames(
            faceNamesByID: faceNamesByID,
            edgeNamesByID: edgeNamesByID,
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

    private func stableSubshapeKey(_ subshapeID: SubshapeID) -> String {
        "feature:\(subshapeID.featureID.description)/role:\(subshapeID.role)/ordinal:\(subshapeID.ordinal)"
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

    private func angle(between lhs: Vector3D, and rhs: Vector3D) -> Double {
        let dot = min(1.0, max(-1.0, lhs.dot(rhs)))
        return acos(dot)
    }

    private func maxAbs(_ values: [Double]) -> Double {
        values.map(abs).max() ?? 0.0
    }
}
