import Foundation
import SwiftCAD
import RupaCoreTypes

public struct SurfaceContinuityService: Sendable {
    private let pipelineOverride: CADPipeline?
    private let tolerance: ModelingTolerance

    public init(
        pipeline: CADPipeline? = nil,
        tolerance: ModelingTolerance = .standard
    ) {
        self.pipelineOverride = pipeline
        self.tolerance = tolerance
    }

    private struct FaceUse {
        var faceID: FaceID
        var normal: Vector3D
        var isPlanar: Bool
        var surface: Surface3D
        var faceOrientation: Orientation
        var orientedEdge: OrientedEdge
    }

    private struct PersistentTopologyNames {
        var faceNamesByID: [FaceID: String]
        var edgeNamesByID: [EdgeID: [String]]
    }

    public func summarize(
        document: DesignDocument,
        objectRegistry: ObjectTypeRegistry = .builtIn,
        currentEvaluation: DocumentEvaluationContext? = nil,
        currentGeneration: DocumentGeneration? = nil
    ) throws -> SurfaceContinuityResult {
        do {
            try document.validate(objectRegistry: objectRegistry)
        } catch {
            throw EditorError(
                code: .evaluationFailed,
                message: "Document must validate before surface continuity summary: \(String(describing: error))"
            )
        }

        guard document.cadDocument.hasActiveRenderableTopologyFeatures else {
            return SurfaceContinuityResult(
                displayUnit: document.displayUnit,
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
            failurePrefix: "Document must evaluate successfully before surface continuity summary"
        )

        let persistentNames = persistentTopologyNames(in: evaluatedDocument)
        let bSplineFaceIDs = Set(
            evaluatedDocument.brep.faces.compactMap { faceID, face -> FaceID? in
                guard let surface = evaluatedDocument.brep.geometry.surfaces[face.surfaceID],
                      case .bSpline = surface else {
                    return nil
                }
                return faceID
            }
        )
        let edgeUses = try bSplineFaceUsesByEdge(in: evaluatedDocument.brep)
        var adjacencies: [SurfaceContinuityResult.Adjacency] = []
        adjacencies.reserveCapacity(edgeUses.count)
        for (edgeID, uses) in edgeUses {
            guard uses.count == 2 else {
                continue
            }
            adjacencies.append(try surfaceAdjacency(
                edgeID: edgeID,
                firstUse: uses[0],
                secondUse: uses[1],
                persistentNames: persistentNames
            ))
        }
        adjacencies.sort {
            if $0.edgePersistentNames == $1.edgePersistentNames {
                return $0.edgeID < $1.edgeID
            }
            return $0.edgePersistentNames.lexicographicallyPrecedes($1.edgePersistentNames)
        }

        return SurfaceContinuityResult(
            displayUnit: document.displayUnit,
            counts: counts(
                bSplineFaceCount: bSplineFaceIDs.count,
                adjacencies: adjacencies
            ),
            adjacencies: adjacencies,
            diagnostics: diagnostics(for: adjacencies)
        )
    }

    private func bSplineFaceUsesByEdge(in model: BRepModel) throws -> [EdgeID: [FaceUse]] {
        var usesByEdge: [EdgeID: [FaceUse]] = [:]
        for bodyID in model.bodies.keys.sorted(by: { $0.description < $1.description }) {
            guard let body = model.bodies[bodyID] else {
                continue
            }
            for shellID in body.shellIDs {
                guard let shell = model.shells[shellID] else {
                    continue
                }
                for faceID in shell.faceIDs {
                    guard let face = model.faces[faceID],
                          let storedSurface = model.geometry.surfaces[face.surfaceID],
                          case let .bSpline(surface) = storedSurface else {
                        continue
                    }
                    let normal = try faceNormal(face, surface: surface)
                    for loopID in face.loops {
                        guard let loop = model.loops[loopID] else {
                            continue
                        }
                        for orientedEdge in loop.edges {
                            usesByEdge[orientedEdge.edgeID, default: []].append(FaceUse(
                                faceID: faceID,
                                normal: normal,
                                isPlanar: isPlanar(surface),
                                surface: storedSurface,
                                faceOrientation: face.orientation,
                                orientedEdge: orientedEdge
                            ))
                        }
                    }
                }
            }
        }
        return usesByEdge
    }

    private func surfaceAdjacency(
        edgeID: EdgeID,
        firstUse: FaceUse,
        secondUse: FaceUse,
        persistentNames: PersistentTopologyNames
    ) throws -> SurfaceContinuityResult.Adjacency {
        if let sampledAdjacency = try sampledSurfaceAdjacency(
            edgeID: edgeID,
            firstUse: firstUse,
            secondUse: secondUse,
            persistentNames: persistentNames
        ) {
            return sampledAdjacency
        }

        let normalDot = min(1.0, max(-1.0, abs(firstUse.normal.dot(secondUse.normal))))
        let normalAngle = acos(normalDot)
        let hasTangentPlaneContinuity = normalAngle <= max(tolerance.angle, tolerance.distance)
        let hasPlanarCurvatureContinuity = hasTangentPlaneContinuity && firstUse.isPlanar && secondUse.isPlanar
        let continuity: SurfaceContinuityResult.ContinuityLevel
        if hasPlanarCurvatureContinuity {
            continuity = .g2
        } else {
            continuity = hasTangentPlaneContinuity ? .g1 : .g0
        }
        let requiresCurvatureContinuitySolve = continuity == .g1 && !(firstUse.isPlanar && secondUse.isPlanar)
        return SurfaceContinuityResult.Adjacency(
            edgeID: edgeID.description,
            edgePersistentNames: persistentNames.edgeNamesByID[edgeID] ?? [],
            firstFaceID: firstUse.faceID.description,
            secondFaceID: secondUse.faceID.description,
            firstFacePersistentName: persistentNames.faceNamesByID[firstUse.faceID],
            secondFacePersistentName: persistentNames.faceNamesByID[secondUse.faceID],
            continuity: continuity,
            positionGap: 0.0,
            normalAngle: normalAngle,
            curvatureGap: hasPlanarCurvatureContinuity ? 0.0 : nil,
            requiresCurvatureContinuitySolve: requiresCurvatureContinuitySolve
        )
    }

    private func sampledSurfaceAdjacency(
        edgeID: EdgeID,
        firstUse: FaceUse,
        secondUse: FaceUse,
        persistentNames: PersistentTopologyNames
    ) throws -> SurfaceContinuityResult.Adjacency? {
        guard let firstParameterCurve = firstUse.orientedEdge.surfaceParameterCurve,
              let secondParameterCurve = secondUse.orientedEdge.surfaceParameterCurve else {
            return nil
        }
        let secondParameterDirection: SurfaceParameterCurveDirection =
            firstUse.orientedEdge.orientation == secondUse.orientedEdge.orientation ? .forward : .reversed
        let sampler = SurfaceContinuitySampler(modelingTolerance: tolerance)
        let request = try sampler.request(
            first: SurfaceContinuitySamplingSide(
                surface: firstUse.surface,
                parameterCurve: firstParameterCurve,
                parameterDirection: .forward,
                frameOrientation: frameOrientation(for: firstUse)
            ),
            second: SurfaceContinuitySamplingSide(
                surface: secondUse.surface,
                parameterCurve: secondParameterCurve,
                parameterDirection: secondParameterDirection,
                frameOrientation: frameOrientation(for: secondUse)
            ),
            requiredLevel: .curvature,
            tolerances: SurfaceContinuityTolerances.standard(modelingTolerance: tolerance),
            options: SurfaceContinuitySamplingOptions(sampleCount: 5)
        )
        let result = try SurfaceContinuityEvaluator(modelingTolerance: tolerance).evaluate(request)
        return SurfaceContinuityResult.Adjacency(
            edgeID: edgeID.description,
            edgePersistentNames: persistentNames.edgeNamesByID[edgeID] ?? [],
            firstFaceID: firstUse.faceID.description,
            secondFaceID: secondUse.faceID.description,
            firstFacePersistentName: persistentNames.faceNamesByID[firstUse.faceID],
            secondFacePersistentName: persistentNames.faceNamesByID[secondUse.faceID],
            continuity: continuityLevel(from: result.achievedLevel),
            positionGap: result.deviation.maximumPositionDistance,
            normalAngle: result.deviation.maximumNormalAngle,
            curvatureGap: result.deviation.maximumPrincipalCurvatureDistance,
            requiresCurvatureContinuitySolve: false
        )
    }

    private func frameOrientation(for use: FaceUse) -> SurfaceFrameOrientation {
        switch use.faceOrientation {
        case .forward:
            return .forward
        case .reversed:
            return .reversed
        }
    }

    private func continuityLevel(
        from achievedLevel: SurfaceContinuityLevel?
    ) -> SurfaceContinuityResult.ContinuityLevel {
        switch achievedLevel {
        case .curvature:
            return .g2
        case .tangentPlane:
            return .g1
        case .positional:
            return .g0
        case nil:
            return .disconnected
        }
    }

    private func faceNormal(
        _ face: Face,
        surface: BSplineSurface3D
    ) throws -> Vector3D {
        let u = try midpoint(surface.uDomain)
        let v = try midpoint(surface.vDomain)
        let normal = try surface.normal(u: u, v: v, tolerance: tolerance)
        return face.orientation == .forward ? normal : -normal
    }

    private func midpoint(_ domain: ParameterDomain) throws -> Double {
        switch domain {
        case let .closed(lowerBound, upperBound):
            return (lowerBound + upperBound) * 0.5
        case .unbounded, .periodic:
            throw EditorError(
                code: .evaluationFailed,
                message: "B-spline surface continuity requires bounded parameter domains."
            )
        }
    }

    private func isPlanar(_ surface: BSplineSurface3D) -> Bool {
        let points = surface.controlPoints.flatMap { $0 }
        guard let origin = points.first else {
            return false
        }
        var normal: Vector3D?
        for firstIndex in points.indices {
            for secondIndex in points.indices where secondIndex > firstIndex {
                let first = points[firstIndex] - origin
                let second = points[secondIndex] - origin
                let candidate = first.cross(second)
                guard candidate.length > max(tolerance.distance * tolerance.distance, Double.ulpOfOne) else {
                    continue
                }
                do {
                    normal = try candidate.normalized(tolerance: max(tolerance.distance * tolerance.distance, Double.ulpOfOne))
                } catch {
                    return false
                }
                break
            }
            if normal != nil {
                break
            }
        }
        guard let planeNormal = normal else {
            return false
        }
        return points.allSatisfy { point in
            abs((point - origin).dot(planeNormal)) <= tolerance.distance
        }
    }

    private func counts(
        bSplineFaceCount: Int,
        adjacencies: [SurfaceContinuityResult.Adjacency]
    ) -> SurfaceContinuityResult.Counts {
        SurfaceContinuityResult.Counts(
            bSplineFaceCount: bSplineFaceCount,
            sharedEdgeCount: adjacencies.count,
            g0AdjacencyCount: adjacencies.filter { $0.continuity == .g0 }.count,
            g1AdjacencyCount: adjacencies.filter { $0.continuity == .g1 }.count,
            g2AdjacencyCount: adjacencies.filter { $0.continuity == .g2 }.count,
            unresolvedG2AdjacencyCount: adjacencies.filter(\.requiresCurvatureContinuitySolve).count
        )
    }

    private func diagnostics(
        for adjacencies: [SurfaceContinuityResult.Adjacency]
    ) -> [EditorDiagnostic] {
        var result = [
            EditorDiagnostic(
                severity: .info,
                message: "Surface continuity summary completed with \(adjacencies.count) shared B-spline edge adjacency record(s)."
            ),
        ]
        let unresolvedCount = adjacencies.filter(\.requiresCurvatureContinuitySolve).count
        if unresolvedCount > 0 {
            result.append(
                EditorDiagnostic(
                    severity: .warning,
                    message: "\(unresolvedCount) surface adjacency record(s) need sampled boundary curves before G2 continuity can be classified."
                )
            )
        }
        return result
    }

    private func persistentTopologyNames(
        in evaluatedDocument: EvaluatedDocument
    ) -> PersistentTopologyNames {
        var faceNamesByID: [FaceID: String] = [:]
        var edgeNamesByID: [EdgeID: [String]] = [:]
        for (name, reference) in evaluatedDocument.generatedNames {
            let stringName = persistentNameString(name)
            switch reference {
            case .body, .vertex:
                continue
            case .face(let faceID):
                faceNamesByID[faceID] = stringName
            case .edge(let edgeID):
                edgeNamesByID[edgeID, default: []].append(stringName)
            }
        }
        for edgeID in edgeNamesByID.keys {
            edgeNamesByID[edgeID]?.sort()
        }
        return PersistentTopologyNames(
            faceNamesByID: faceNamesByID,
            edgeNamesByID: edgeNamesByID
        )
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
}
