import Foundation
import SwiftCAD

public struct SurfaceSourceSummaryService: Sendable {
    private let pipelineOverride: CADPipeline?

    public init(pipeline: CADPipeline? = nil) {
        self.pipelineOverride = pipeline
    }

    private struct PatchCandidate {
        var patchID: Int
        var boundaryVertexIndices: [Int]
    }

    public func summarize(
        document: DesignDocument,
        objectRegistry: ObjectTypeRegistry = .builtIn,
        currentEvaluation: DocumentEvaluationContext? = nil,
        currentGeneration: DocumentGeneration? = nil
    ) throws -> SurfaceSourceSummaryResult {
        do {
            try document.validate(objectRegistry: objectRegistry)
        } catch {
            throw EditorError(
                code: .evaluationFailed,
                message: "Document must validate before surface source summary: \(String(describing: error))"
            )
        }

        let sceneNodeIDsByFeatureID = sceneNodeIDsByFeatureID(in: document)
        let topologyEntriesByPersistentName = try topologyEntriesByPersistentName(
            document: document,
            objectRegistry: objectRegistry,
            currentEvaluation: currentEvaluation,
            currentGeneration: currentGeneration
        )
        let sources = document.cadDocument.designGraph.order.compactMap { featureID -> SurfaceSourceSummaryResult.Source? in
            guard let feature = document.cadDocument.designGraph.nodes[featureID],
                  feature.isSuppressed == false,
                  case let .polySpline(polySpline) = feature.operation else {
                return nil
            }
            return source(
                featureID: featureID,
                feature: feature,
                polySpline: polySpline,
                sceneNodeID: sceneNodeIDsByFeatureID[featureID],
                topologyEntriesByPersistentName: topologyEntriesByPersistentName
            )
        }

        return SurfaceSourceSummaryResult(
            displayUnit: document.displayUnit,
            counts: counts(for: sources),
            sources: sources,
            diagnostics: [
                EditorDiagnostic(
                    severity: .info,
                    message: "Surface source summary completed with \(sources.count) source-owned surface feature(s)."
                ),
            ]
        )
    }

    private func source(
        featureID: FeatureID,
        feature: FeatureNode,
        polySpline: PolySplineFeature,
        sceneNodeID: SceneNodeID?,
        topologyEntriesByPersistentName: [String: TopologySummaryResult.Entry]
    ) -> SurfaceSourceSummaryResult.Source {
        let analysis = PolySplineMeshAnalysisService().analyze(
            sourceMesh: polySpline.sourceMesh,
            options: polySpline.options
        )
        let patchCandidates = selectedPatchCandidates(
            from: analysis,
            sourceMesh: polySpline.sourceMesh
        )
        let patches = patchCandidates.map { patchCandidate in
            patch(
                featureID: featureID,
                patchCandidate: patchCandidate,
                sourceMesh: polySpline.sourceMesh,
                topologyEntriesByPersistentName: topologyEntriesByPersistentName
            )
        }
        return SurfaceSourceSummaryResult.Source(
            featureID: featureID.description,
            name: feature.name ?? "PolySpline Surface",
            sceneNodeID: sceneNodeID?.description,
            kind: "polySpline",
            meshCounts: SurfaceSourceSummaryResult.MeshCounts(
                vertexCount: analysis.vertexCount,
                usedVertexCount: analysis.usedVertexCount,
                triangleCount: analysis.triangleCount,
                indexedElementCount: analysis.indexedElementCount,
                boundaryEdgeCount: analysis.boundaryEdgeCount,
                internalEdgeCount: analysis.internalEdgeCount
            ),
            options: SurfaceSourceSummaryResult.PolySplineOptionsSummary(
                roundedCorners: polySpline.options.roundedCorners,
                mergePatches: polySpline.options.mergePatches,
                interpolateBoundaryExactly: polySpline.options.interpolateBoundaryExactly
            ),
            support: SurfaceSourceSummaryResult.SupportSummary(
                isSupported: analysis.isSupported,
                candidateKind: analysis.candidateKind?.rawValue,
                supportedPatchCount: analysis.supportedPatchCount,
                candidatePatchCount: analysis.candidatePatchCount,
                failureMessage: analysis.failureMessage
            ),
            patches: patches,
            adjacencies: adjacencies(
                featureID: featureID,
                analysis: analysis,
                topologyEntriesByPersistentName: topologyEntriesByPersistentName
            ),
            diagnostics: analysis.diagnostics.map { diagnostic in
                SurfaceSourceSummaryResult.Diagnostic(
                    severity: diagnostic.severity.rawValue,
                    code: diagnostic.code.rawValue,
                    message: diagnostic.message,
                    vertexIndices: diagnostic.vertexIndices,
                    triangleIndices: diagnostic.triangleIndices
                )
            }
        )
    }

    private func patch(
        featureID: FeatureID,
        patchCandidate: PatchCandidate,
        sourceMesh: Mesh,
        topologyEntriesByPersistentName: [String: TopologySummaryResult.Entry]
    ) -> SurfaceSourceSummaryResult.Patch {
        let patchID = patchCandidate.patchID
        let facePersistentName = persistentName(
            featureID: featureID,
            subshape: "patch:\(patchID):face"
        )
        let faceSelectionComponentID = topologyEntriesByPersistentName[facePersistentName]?.selectionComponentID
        let edgePersistentNames = edgeRoles.map {
            persistentName(featureID: featureID, subshape: "patch:\(patchID):\($0.subshape)")
        }
        .filter { topologyEntriesByPersistentName[$0] != nil }
        let controlVertices = zip(vertexRoles, patchCandidate.boundaryVertexIndices).map { role, sourceVertexIndex in
            controlVertex(
                featureID: featureID,
                patchID: patchID,
                role: role,
                sourceVertexIndex: sourceVertexIndex,
                sourceMesh: sourceMesh
            )
        }
        return SurfaceSourceSummaryResult.Patch(
            patchID: patchID,
            facePersistentName: topologyEntriesByPersistentName[facePersistentName]?.persistentName,
            faceSelectionComponentID: faceSelectionComponentID,
            uDomain: SurfaceSourceSummaryResult.ParameterRange(lowerBound: 0.0, upperBound: 1.0),
            vDomain: SurfaceSourceSummaryResult.ParameterRange(lowerBound: 0.0, upperBound: 1.0),
            basis: cubicBezierBasis(),
            controlVertices: controlVertices,
            trimLoops: [
                SurfaceSourceSummaryResult.TrimLoop(
                    role: "outer",
                    parameterAddresses: cornerParameterAddresses(),
                    sourceVertexIndices: patchCandidate.boundaryVertexIndices,
                    edgePersistentNames: edgePersistentNames
                ),
            ],
            parameterAddresses: patchParameterAddresses()
        )
    }

    private func controlVertex(
        featureID: FeatureID,
        patchID: Int,
        role: (id: String, subshape: String),
        sourceVertexIndex: Int,
        sourceMesh: Mesh
    ) -> SurfaceSourceSummaryResult.ControlVertex {
        let generatedVertexPersistentName = persistentName(
            featureID: featureID,
            subshape: "patch:\(patchID):\(role.subshape)"
        )
        let point: Point3D
        if sourceMesh.positions.indices.contains(sourceVertexIndex) {
            point = sourceMesh.positions[sourceVertexIndex]
        } else {
            point = Point3D(x: 0.0, y: 0.0, z: 0.0)
        }
        return SurfaceSourceSummaryResult.ControlVertex(
            id: "feature:\(featureID.description)/patch:\(patchID)/cv:\(role.id)",
            role: role.id,
            sourceVertexIndex: sourceVertexIndex,
            point: SurfaceSourceSummaryResult.Point(x: point.x, y: point.y, z: point.z),
            generatedVertexPersistentName: generatedVertexPersistentName,
            selectionComponentID: SelectionComponentID
                .generatedTopology(generatedVertexPersistentName)
                .rawValue
        )
    }

    private func adjacencies(
        featureID: FeatureID,
        analysis: PolySplineMeshAnalysisResult,
        topologyEntriesByPersistentName: [String: TopologySummaryResult.Entry]
    ) -> [SurfaceSourceSummaryResult.Adjacency] {
        guard let patchGraph = analysis.patchGraph else {
            return []
        }
        let selectedPatchIDs = Set(selectedPatchIDs(from: patchGraph))
        let candidatesByID = Dictionary(uniqueKeysWithValues: patchGraph.candidates.map { ($0.id, $0) })
        return patchGraph.selectedAdjacencies
            .filter {
                selectedPatchIDs.contains($0.firstCandidateID)
                    && selectedPatchIDs.contains($0.secondCandidateID)
            }
            .map { adjacency in
                let sharedEdgePersistentName = sharedEdgePersistentName(
                    featureID: featureID,
                    adjacency: adjacency,
                    candidatesByID: candidatesByID,
                    topologyEntriesByPersistentName: topologyEntriesByPersistentName
                )
                return SurfaceSourceSummaryResult.Adjacency(
                    firstPatchID: adjacency.firstCandidateID,
                    secondPatchID: adjacency.secondCandidateID,
                    sharedVertexIndices: adjacency.sharedVertexIndices,
                    sharedEdgePersistentName: sharedEdgePersistentName,
                    continuityLevel: adjacency.continuityLevel.rawValue,
                    normalAngleRadians: adjacency.normalAngleRadians,
                    requiresCurvatureContinuitySolve: adjacency.requiresCurvatureContinuitySolve
                )
            }
    }

    private func sharedEdgePersistentName(
        featureID: FeatureID,
        adjacency: PolySplinePatchGraph.SelectedAdjacency,
        candidatesByID: [Int: PolySplinePatchGraph.QuadCandidate],
        topologyEntriesByPersistentName: [String: TopologySummaryResult.Entry]
    ) -> String? {
        guard let firstCandidate = candidatesByID[adjacency.firstCandidateID] else {
            return nil
        }
        let sharedVertexSet = Set(adjacency.sharedVertexIndices)
        for index in firstCandidate.boundaryVertexIndices.indices {
            let nextIndex = (index + 1) % firstCandidate.boundaryVertexIndices.count
            let edgeVertexSet = Set([
                firstCandidate.boundaryVertexIndices[index],
                firstCandidate.boundaryVertexIndices[nextIndex],
            ])
            guard edgeVertexSet == sharedVertexSet,
                  edgeRoles.indices.contains(index) else {
                continue
            }
            let candidateName = persistentName(
                featureID: featureID,
                subshape: "patch:\(adjacency.firstCandidateID):\(edgeRoles[index].subshape)"
            )
            return topologyEntriesByPersistentName[candidateName]?.persistentName
        }
        return nil
    }

    private func selectedPatchCandidates(
        from analysis: PolySplineMeshAnalysisResult,
        sourceMesh: Mesh
    ) -> [PatchCandidate] {
        guard analysis.isSupported else {
            return []
        }
        if let patchGraph = analysis.patchGraph {
            let candidatesByID = Dictionary(uniqueKeysWithValues: patchGraph.candidates.map { ($0.id, $0) })
            return selectedPatchIDs(from: patchGraph).compactMap { patchID in
                guard let candidate = candidatesByID[patchID] else {
                    return nil
                }
                return PatchCandidate(
                    patchID: patchID,
                    boundaryVertexIndices: candidate.boundaryVertexIndices
                )
            }
        }
        guard let boundaryVertexIndices = singleQuadBoundaryVertexIndices(in: sourceMesh) else {
            return []
        }
        return [
            PatchCandidate(
                patchID: 0,
                boundaryVertexIndices: boundaryVertexIndices
            ),
        ]
    }

    private func selectedPatchIDs(from patchGraph: PolySplinePatchGraph) -> [Int] {
        if let partition = patchGraph.partition,
           partition.isComplete {
            return partition.selectedCandidateIDs
        }
        if patchGraph.candidates.count == 1,
           let candidate = patchGraph.candidates.first {
            return [candidate.id]
        }
        return []
    }

    private func singleQuadBoundaryVertexIndices(in mesh: Mesh) -> [Int]? {
        guard mesh.indices.count == 6 else {
            return nil
        }
        var edgeUseCounts: [MeshEdge: Int] = [:]
        var directedBoundaryEdges: [(start: Int, end: Int)] = []
        let triangleCount = mesh.indices.count / 3
        for triangleIndex in 0..<triangleCount {
            let offset = triangleIndex * 3
            let first = Int(mesh.indices[offset])
            let second = Int(mesh.indices[offset + 1])
            let third = Int(mesh.indices[offset + 2])
            let directedEdges = [
                (start: first, end: second),
                (start: second, end: third),
                (start: third, end: first),
            ]
            for edge in directedEdges {
                edgeUseCounts[MeshEdge(edge.start, edge.end), default: 0] += 1
            }
        }
        for triangleIndex in 0..<triangleCount {
            let offset = triangleIndex * 3
            let first = Int(mesh.indices[offset])
            let second = Int(mesh.indices[offset + 1])
            let third = Int(mesh.indices[offset + 2])
            let directedEdges = [
                (start: first, end: second),
                (start: second, end: third),
                (start: third, end: first),
            ]
            directedBoundaryEdges.append(
                contentsOf: directedEdges.filter { edgeUseCounts[MeshEdge($0.start, $0.end)] == 1 }
            )
        }
        var nextByStart: [Int: Int] = [:]
        var incomingByEnd: [Int: Int] = [:]
        for edge in directedBoundaryEdges {
            guard nextByStart[edge.start] == nil,
                  incomingByEnd[edge.end] == nil else {
                return nil
            }
            nextByStart[edge.start] = edge.end
            incomingByEnd[edge.end] = edge.start
        }
        guard nextByStart.count == 4,
              Set(nextByStart.keys) == Set(incomingByEnd.keys),
              let start = nextByStart.keys.min() else {
            return nil
        }
        var ordered = [start]
        var current = start
        while ordered.count < 4 {
            guard let next = nextByStart[current],
                  next != start else {
                return nil
            }
            ordered.append(next)
            current = next
        }
        guard nextByStart[current] == start else {
            return nil
        }
        return ordered
    }

    private func topologyEntriesByPersistentName(
        document: DesignDocument,
        objectRegistry: ObjectTypeRegistry,
        currentEvaluation: DocumentEvaluationContext?,
        currentGeneration: DocumentGeneration?
    ) throws -> [String: TopologySummaryResult.Entry] {
        let summary = try TopologySummaryService(pipeline: pipelineOverride).summarize(
            document: document,
            objectRegistry: objectRegistry,
            currentEvaluation: currentEvaluation,
            currentGeneration: currentGeneration
        )
        return Dictionary(uniqueKeysWithValues: summary.entries.map { ($0.persistentName, $0) })
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

    private func counts(
        for sources: [SurfaceSourceSummaryResult.Source]
    ) -> SurfaceSourceSummaryResult.Counts {
        SurfaceSourceSummaryResult.Counts(
            sourceCount: sources.count,
            patchCount: sources.reduce(0) { $0 + $1.patches.count },
            controlVertexCount: sources.reduce(0) { partial, source in
                partial + source.patches.reduce(0) { $0 + $1.controlVertices.count }
            },
            trimLoopCount: sources.reduce(0) { partial, source in
                partial + source.patches.reduce(0) { $0 + $1.trimLoops.count }
            },
            adjacencyCount: sources.reduce(0) { $0 + $1.adjacencies.count }
        )
    }

    private func persistentName(featureID: FeatureID, subshape: String) -> String {
        "feature:\(featureID.description)/generated:polySpline/subshape:\(subshape)"
    }

    private func cubicBezierBasis() -> SurfaceSourceSummaryResult.Basis {
        SurfaceSourceSummaryResult.Basis(
            kind: "cubicBezierBSpline",
            uDegree: 3,
            vDegree: 3,
            uOrder: 4,
            vOrder: 4,
            uKnots: [0.0, 0.0, 0.0, 0.0, 1.0, 1.0, 1.0, 1.0],
            vKnots: [0.0, 0.0, 0.0, 0.0, 1.0, 1.0, 1.0, 1.0],
            uSpanCount: 1,
            vSpanCount: 1,
            isRational: false
        )
    }

    private func patchParameterAddresses() -> [SurfaceSourceSummaryResult.ParameterAddress] {
        cornerParameterAddresses() + [
            SurfaceSourceSummaryResult.ParameterAddress(id: "center", u: 0.5, v: 0.5),
        ]
    }

    private func cornerParameterAddresses() -> [SurfaceSourceSummaryResult.ParameterAddress] {
        [
            SurfaceSourceSummaryResult.ParameterAddress(id: "uMin:vMin", u: 0.0, v: 0.0),
            SurfaceSourceSummaryResult.ParameterAddress(id: "uMax:vMin", u: 1.0, v: 0.0),
            SurfaceSourceSummaryResult.ParameterAddress(id: "uMax:vMax", u: 1.0, v: 1.0),
            SurfaceSourceSummaryResult.ParameterAddress(id: "uMin:vMax", u: 0.0, v: 1.0),
        ]
    }

    private var vertexRoles: [(id: String, subshape: String)] {
        [
            ("uMin:vMin", "vertex:uMin:vMin"),
            ("uMax:vMin", "vertex:uMax:vMin"),
            ("uMax:vMax", "vertex:uMax:vMax"),
            ("uMin:vMax", "vertex:uMin:vMax"),
        ]
    }

    private var edgeRoles: [(id: String, subshape: String)] {
        [
            ("vMin", "edge:vMin"),
            ("uMax", "edge:uMax"),
            ("vMax", "edge:vMax"),
            ("uMin", "edge:uMin"),
        ]
    }

    private struct MeshEdge: Hashable {
        var first: Int
        var second: Int

        init(_ first: Int, _ second: Int) {
            self.first = min(first, second)
            self.second = max(first, second)
        }
    }

}
