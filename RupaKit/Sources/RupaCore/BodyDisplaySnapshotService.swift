import Foundation
import SwiftCAD
import RupaCoreTypes

public struct BodyDisplaySnapshotService: Sendable {
    private let pipelineOverride: CADPipeline?
    private let identityResolver = GeneratedBodyIdentityResolver()
    private let boundaryLoopResolver = OpenBoundaryLoopResolver()

    public init(pipeline: CADPipeline? = nil) {
        self.pipelineOverride = pipeline
    }

    public func snapshots(
        document: DesignDocument,
        objectRegistry: ObjectTypeRegistry = .builtIn,
        currentEvaluation: DocumentEvaluationContext? = nil,
        currentGeneration: DocumentGeneration? = nil
    ) throws -> [FeatureID: BodyDisplaySnapshot] {
        let evaluatedDocument = try DocumentEvaluationContextResolver(
            pipeline: pipelineOverride
        ).evaluatedDocument(
            document: document,
            objectRegistry: objectRegistry,
            currentEvaluation: currentEvaluation,
            currentGeneration: currentGeneration,
            failurePrefix: "Document must evaluate successfully before body display snapshots"
        )
        return snapshots(evaluatedDocument: evaluatedDocument)
    }

    public func snapshots(
        evaluatedDocument: EvaluatedDocument
    ) -> [FeatureID: BodyDisplaySnapshot] {
        var snapshots: [FeatureID: BodyDisplaySnapshot] = [:]
        for featureID in identityResolver.bodyFeatureIDs(in: evaluatedDocument.subshapes) {
            guard let snapshot = snapshot(
                for: featureID,
                in: evaluatedDocument
            ) else {
                continue
            }
            snapshots[featureID] = snapshot
        }
        return snapshots
    }

    private func snapshot(
        for featureID: FeatureID,
        in evaluatedDocument: EvaluatedDocument
    ) -> BodyDisplaySnapshot? {
        guard let identity = identityResolver.firstBodyIdentity(
            for: featureID,
            in: evaluatedDocument.subshapes
        ),
              let mesh = evaluatedDocument.meshes[identity.bodyID],
              let bounds = bodyBounds(mesh.positions) else {
            return nil
        }

        return BodyDisplaySnapshot(
            featureID: featureID,
            bodyID: identity.bodyID.description,
            subshapeID: GeneratedSubshapeIdentity.string(for: identity.subshapeID),
            bounds: bounds,
            mesh: BodyDisplaySnapshot.Mesh(
                positions: mesh.positions,
                indices: mesh.indices
            ),
            topology: topology(
                for: featureID,
                bodyID: identity.bodyID,
                mesh: mesh,
                in: evaluatedDocument
            )
        )
    }

    private func topology(
        for featureID: FeatureID,
        bodyID: BodyID,
        mesh: SwiftCAD.Mesh,
        in evaluatedDocument: EvaluatedDocument
    ) -> BodyDisplaySnapshot.Topology {
        let model = evaluatedDocument.brep
        var faces: [BodyDisplaySnapshot.Topology.Face] = []
        var edges: [BodyDisplaySnapshot.Topology.Edge] = []
        var vertices: [BodyDisplaySnapshot.Topology.Vertex] = []
        let generatedEntries = evaluatedDocument.subshapes.entries.sorted(by: {
            GeneratedSubshapeIdentity.areInIncreasingOrder($0.key, $1.key)
        })
        var edgeSubshapeIDs: [EdgeID: SubshapeID] = [:]
        var edgeDisplayPointsByID: [EdgeID: [Point3D]] = [:]
        var adjacentFacesByEdgeID: [EdgeID: [SubshapeID]] = [:]
        var seenFaces: Set<FaceID> = []
        for (subshapeID, reference) in generatedEntries where subshapeID.featureID == featureID {
            guard case .face(let faceID) = reference,
                  seenFaces.insert(faceID).inserted,
                  let face = model.faces[faceID] else { continue }
            var seenEdges: Set<EdgeID> = []
            for loopID in face.loops {
                guard let loop = model.loops[loopID] else { continue }
                for coedge in loop.edges where seenEdges.insert(coedge.edgeID).inserted {
                    adjacentFacesByEdgeID[coedge.edgeID, default: []].append(subshapeID)
                }
            }
        }
        for (subshapeID, reference) in generatedEntries where subshapeID.featureID == featureID {
            guard case .edge(let edgeID) = reference else { continue }
            if edgeSubshapeIDs[edgeID] == nil {
                edgeSubshapeIDs[edgeID] = subshapeID
                if let edge = model.edges[edgeID] {
                    edgeDisplayPointsByID[edgeID] = edgeDisplayPoints(
                        edge, model: model,
                        tolerance: evaluatedDocument.configuration.tolerance,
                        tessellationOptions: evaluatedDocument.configuration.tessellationOptions
                            .featureOverrides[featureID]
                            ?? evaluatedDocument.configuration.tessellationOptions
                    )
                }
            }
        }
        var openBoundaryLoopIDByEdgeID: [EdgeID: String] = [:]
        if let body = model.bodies[bodyID] {
            for loop in boundaryLoopResolver.loops(in: body, model: model)
            where loop.traversals.isEmpty == false {
                let stableSubshapeIDs = loop.traversals.compactMap { edgeSubshapeIDs[$0.edgeID] }
                guard stableSubshapeIDs.count == loop.traversals.count,
                      let canonicalID = stableSubshapeIDs.min(by: GeneratedSubshapeIdentity.areInIncreasingOrder) else {
                    continue
                }
                var loopDisplayPoints: [EdgeID: [Point3D]] = [:]
                for traversal in loop.traversals {
                    guard let points = edgeDisplayPointsByID[traversal.edgeID] else {
                        loopDisplayPoints.removeAll(keepingCapacity: false)
                        break
                    }
                    loopDisplayPoints[traversal.edgeID] = points
                }
                guard loopDisplayPoints.count == loop.traversals.count else { continue }
                let loopID = GeneratedSubshapeIdentity.string(for: canonicalID)
                for traversal in loop.traversals {
                    openBoundaryLoopIDByEdgeID[traversal.edgeID] = loopID
                    edgeDisplayPointsByID[traversal.edgeID] = loopDisplayPoints[traversal.edgeID]
                }
            }
        }
        // Every generated face of this feature, whether or not it also has the
        // outer-loop polygon `faces` requires, so that mesh provenance is
        // resolved from the kernel's own record rather than from what a polygon
        // hit test happened to be able to represent.
        var faceComponentIDs: [FaceID: SelectionComponentID] = [:]

        for (subshapeID, reference) in generatedEntries {
            guard subshapeID.featureID == featureID else {
                continue
            }
            let componentID = SelectionComponentID.generatedTopology(subshapeID)
            switch reference {
            case .body:
                continue
            case .face(let faceID):
                faceComponentIDs[faceID] = componentID
                guard let face = model.faces[faceID],
                      let points = orderedOuterLoopPoints(for: face, in: model),
                      points.count >= 3 else {
                    continue
                }
                faces.append(BodyDisplaySnapshot.Topology.Face(
                    componentID: componentID,
                    points: points
                ))
            case .edge(let edgeID):
                guard let edge = model.edges[edgeID],
                      let start = model.vertices[edge.startVertexID]?.point,
                      let end = model.vertices[edge.endVertexID]?.point else {
                    continue
                }
                // A frame that cannot be built leaves the edge without treatment handles and
                // says why, rather than dropping them without a word.
                var affordanceFrame: BodyDisplaySnapshot.Topology.Edge.AffordanceFrame?
                var affordanceFrameFailure: String?
                do {
                    affordanceFrame = try edgeAffordanceFrame(
                        subshapeID: subshapeID,
                        adjacentFaces: adjacentFacesByEdgeID[edgeID] ?? [],
                        in: evaluatedDocument
                    )
                } catch {
                    affordanceFrameFailure = error.localizedDescription
                }
                edges.append(BodyDisplaySnapshot.Topology.Edge(
                    componentID: componentID,
                    start: start,
                    end: end,
                    displayPoints: edgeDisplayPointsByID[edgeID] ?? [],
                    openBoundaryLoopID: openBoundaryLoopIDByEdgeID[edgeID],
                    affordanceFrame: affordanceFrame,
                    affordanceFrameFailure: affordanceFrameFailure
                ))
            case .vertex(let vertexID):
                guard let vertex = model.vertices[vertexID] else {
                    continue
                }
                vertices.append(BodyDisplaySnapshot.Topology.Vertex(
                    componentID: componentID,
                    point: vertex.point
                ))
            }
        }

        return BodyDisplaySnapshot.Topology(
            faces: faces,
            edges: edges,
            vertices: vertices,
            meshFaceRuns: meshFaceRuns(for: mesh, componentIDs: faceComponentIDs)
        )
    }

    private func edgeAffordanceFrame(
        subshapeID: SubshapeID,
        adjacentFaces: [SubshapeID],
        in document: EvaluatedDocument
    ) throws -> BodyDisplaySnapshot.Topology.Edge.AffordanceFrame? {
        // An edge no face bounds has nothing to frame it; that is not a failure.
        guard !adjacentFaces.isEmpty else { return nil }
        let tolerance = document.configuration.tolerance
        let reference = try document.stableSubshapeReference(for: subshapeID)
        let anchor = try EdgeQueryEvaluator(tolerance: tolerance).midpoint(
            of: EdgeReference(subshape: reference), in: document
        ).point
        let query = SurfaceQueryEvaluator(tolerance: tolerance)
        var normals: [Vector3D] = []
        for faceID in adjacentFaces {
            let faceReference = try document.stableSubshapeReference(for: faceID)
            // The anchor already belongs to this edge's incident face. Query
            // its support directly to avoid trim-boundary rounding rejection.
            let frame = try query.outwardFrame(
                nearestTo: anchor,
                on: SurfaceReference(subshape: faceReference),
                in: document,
                options: SurfaceProjectionOptions(respectsTrimBounds: false)
            )
            guard (frame.point - anchor).length <= tolerance.distance,
                  frame.outwardNormal.isFinite,
                  frame.outwardNormal.length > 0 else {
                throw EditorError(
                    code: .commandFailed,
                    message: "The edge's midpoint does not lie on an adjacent face with a defined normal."
                )
            }
            normals.append(frame.outwardNormal * (1 / frame.outwardNormal.length))
        }
        return .init(anchor: anchor, adjacentFaceNormals: normals)
    }

    private func edgeDisplayPoints(
        _ edge: Edge,
        model: BRepModel,
        tolerance: ModelingTolerance,
        tessellationOptions: TessellationOptions
    ) -> [Point3D]? {
        guard let curve = model.geometry.curves[edge.curveID],
              let start = model.vertices[edge.startVertexID]?.point,
              let end = model.vertices[edge.endVertexID]?.point else {
            return nil
        }
        do {
            let validatedCurve = try ValidatedCurve3D(curve, tolerance: tolerance)
            let startParameter = try edge.trim?.startParameter
                ?? validatedCurve.parameterProjection(of: start).parameter
            let endParameter = try edge.trim?.endParameter
                ?? validatedCurve.parameterProjection(of: end).parameter
            guard startParameter.isFinite, endParameter.isFinite,
                  startParameter != endParameter else {
                return nil
            }
            let curveStart = try validatedCurve.point(at: startParameter)
            let curveEnd = try validatedCurve.point(at: endParameter)
            guard (curveStart - start).length <= tolerance.distance,
                  (curveEnd - end).length <= tolerance.distance else {
                return nil
            }
            let initialSegmentCount = displayCurveInitialSegmentCount(
                for: curve,
                from: startParameter,
                to: endParameter
            )
            let maximumSegmentCount = 4_096
            guard initialSegmentCount <= maximumSegmentCount else { return nil }

            var points: [Point3D] = []
            points.reserveCapacity(initialSegmentCount + 1)
            var processedSegmentCount = 0

            func append(
                from lowerParameter: Double,
                lowerPoint: Point3D,
                to upperParameter: Double,
                upperPoint: Point3D,
                depth: Int
            ) throws -> Bool {
                processedSegmentCount += 1
                guard processedSegmentCount <= maximumSegmentCount * 2 - 1 else {
                    return false
                }
                let middleParameter = lowerParameter + (upperParameter - lowerParameter) * 0.5
                guard middleParameter > min(lowerParameter, upperParameter),
                      middleParameter < max(lowerParameter, upperParameter) else {
                    return false
                }
                let middlePoint = try validatedCurve.point(at: middleParameter)
                let chord = upperPoint - lowerPoint
                let chordLength = chord.length
                guard chordLength.isFinite, chordLength > tolerance.distance else {
                    return false
                }
                let chordDirection = try chord.normalized(tolerance: tolerance.distance)
                let differential = try validatedCurve.differentialGeometry(at: middleParameter)
                let tangent = try differential.firstDerivative.normalized(tolerance: tolerance.distance)
                let orientedTangent = upperParameter > lowerParameter ? tangent : -tangent
                let tangentDot = min(max(chordDirection.dot(orientedTangent), -1), 1)
                let tangentDeviation = acos(tangentDot)
                let deviation = pointToSegmentDistance(
                    middlePoint,
                    start: lowerPoint,
                    end: upperPoint
                )
                let satisfiesEdgeLength = tessellationOptions.maxEdgeLength.map {
                    chordLength <= $0
                } ?? true
                if deviation <= tessellationOptions.linearTolerance,
                   tangentDeviation <= tessellationOptions.angularTolerance,
                   satisfiesEdgeLength {
                    points.append(upperPoint)
                    return points.count <= maximumSegmentCount + 1
                }
                guard depth < 24 else { return false }
                return try append(
                    from: lowerParameter,
                    lowerPoint: lowerPoint,
                    to: middleParameter,
                    upperPoint: middlePoint,
                    depth: depth + 1
                ) && append(
                    from: middleParameter,
                    lowerPoint: middlePoint,
                    to: upperParameter,
                    upperPoint: upperPoint,
                    depth: depth + 1
                )
            }

            var lowerParameter = startParameter
            var lowerPoint = start
            points.append(start)
            for index in 1...initialSegmentCount {
                let fraction = Double(index) / Double(initialSegmentCount)
                let upperParameter = startParameter + (endParameter - startParameter) * fraction
                let upperPoint = index == initialSegmentCount
                    ? end
                    : try validatedCurve.point(at: upperParameter)
                guard try append(
                    from: lowerParameter,
                    lowerPoint: lowerPoint,
                    to: upperParameter,
                    upperPoint: upperPoint,
                    depth: 0
                ) else {
                    return nil
                }
                lowerParameter = upperParameter
                lowerPoint = upperPoint
            }
            return points.count >= 2 ? points : nil
        } catch {
            return nil
        }
    }

    private func displayCurveInitialSegmentCount(
        for curve: Curve3D,
        from start: Double,
        to end: Double
    ) -> Int {
        let minimumSegmentCount = 32
        switch curve {
        case .line:
            return 1
        case .bSpline(let spline):
            let lower = min(start, end)
            let upper = max(start, end)
            let spanCount = spline.knots.indices.dropFirst().reduce(into: 0) { count, index in
                guard spline.knots[index] > lower,
                      spline.knots[index - 1] < upper,
                      spline.knots[index] > spline.knots[index - 1] else { return }
                count += 1
            }
            return max(minimumSegmentCount, min(spanCount * 8, 1_024))
        default:
            return minimumSegmentCount
        }
    }

    private func pointToSegmentDistance(
        _ point: Point3D,
        start: Point3D,
        end: Point3D
    ) -> Double {
        let direction = end - start
        let lengthSquared = direction.dot(direction)
        guard lengthSquared > 0 else { return (point - start).length }
        let fraction = min(max((point - start).dot(direction) / lengthSquared, 0), 1)
        return (point - (start + direction * fraction)).length
    }

    /// Converts the kernel's per-face triangle counts into triangle ranges.
    ///
    /// The kernel records the runs contiguously in emission order, so the range
    /// of a run starts where the previous one ended. A run whose face has no
    /// generated-topology identity is omitted: that face carries no stable name
    /// a selection can refer to, so reporting no component is the truthful
    /// answer for its triangles rather than a substituted one.
    private func meshFaceRuns(
        for mesh: SwiftCAD.Mesh,
        componentIDs: [FaceID: SelectionComponentID]
    ) -> [BodyDisplaySnapshot.Topology.MeshFaceRun] {
        var runs: [BodyDisplaySnapshot.Topology.MeshFaceRun] = []
        runs.reserveCapacity(mesh.faceRuns.count)
        var triangleStart = 0
        for run in mesh.faceRuns {
            let triangleEnd = triangleStart + run.triangleCount
            defer { triangleStart = triangleEnd }
            guard let componentID = componentIDs[run.faceID] else {
                continue
            }
            runs.append(BodyDisplaySnapshot.Topology.MeshFaceRun(
                componentID: componentID,
                triangleRange: triangleStart ..< triangleEnd
            ))
        }
        return runs
    }

    private func orderedOuterLoopPoints(
        for face: CADFace,
        in model: CADBRepModel
    ) -> [Point3D]? {
        guard let loopID = face.loops.first(where: { loopID in
            model.loops[loopID]?.role == .outer
        }) else {
            return nil
        }
        do {
            return try model.orderedPoints(for: loopID)
        } catch {
            return nil
        }
    }

    private func bodyBounds(_ positions: [Point3D]) -> BodyDisplaySnapshot.Bounds? {
        guard let first = positions.first else {
            return nil
        }
        var bounds = BodyDisplaySnapshot.Bounds(
            minX: first.x,
            minY: first.y,
            minZ: first.z,
            maxX: first.x,
            maxY: first.y,
            maxZ: first.z
        )
        for point in positions.dropFirst() {
            bounds.minX = min(bounds.minX, point.x)
            bounds.minY = min(bounds.minY, point.y)
            bounds.minZ = min(bounds.minZ, point.z)
            bounds.maxX = max(bounds.maxX, point.x)
            bounds.maxY = max(bounds.maxY, point.y)
            bounds.maxZ = max(bounds.maxZ, point.z)
        }
        return bounds
    }

}
