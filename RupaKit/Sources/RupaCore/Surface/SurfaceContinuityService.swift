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
        let adjacencies = edgeUses.compactMap { edgeID, uses -> SurfaceContinuityResult.Adjacency? in
            guard uses.count == 2 else {
                return nil
            }
            return surfaceAdjacency(
                edgeID: edgeID,
                firstUse: uses[0],
                secondUse: uses[1],
                persistentNames: persistentNames
            )
        }
        .sorted {
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
                    let faceUse = FaceUse(
                        faceID: faceID,
                        normal: normal,
                        isPlanar: isPlanar(surface)
                    )
                    for loopID in face.loops {
                        guard let loop = model.loops[loopID] else {
                            continue
                        }
                        for orientedEdge in loop.edges {
                            usesByEdge[orientedEdge.edgeID, default: []].append(faceUse)
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
    ) -> SurfaceContinuityResult.Adjacency {
        let normalDot = min(1.0, max(-1.0, abs(firstUse.normal.dot(secondUse.normal))))
        let normalAngle = acos(normalDot)
        let hasTangentPlaneContinuity = normalAngle <= max(tolerance.angle, tolerance.distance)
        let continuity: SurfaceContinuityResult.ContinuityLevel = hasTangentPlaneContinuity ? .g1 : .g0
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
            curvatureGap: nil,
            requiresCurvatureContinuitySolve: requiresCurvatureContinuitySolve
        )
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
                    message: "\(unresolvedCount) surface adjacency record(s) require curvature-continuity solving before G2 can be claimed."
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
