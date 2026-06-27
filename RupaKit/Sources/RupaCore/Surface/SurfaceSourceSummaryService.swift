import Foundation
import SwiftCAD
import RupaCoreTypes

public struct SurfaceSourceSummaryService: Sendable {
    private let pipelineOverride: CADPipeline?

    public init(pipeline: CADPipeline? = nil) {
        self.pipelineOverride = pipeline
    }

    private struct PatchCandidate {
        var patchID: Int
        var boundaryVertexIndices: [Int]
    }

    private struct SurfaceVertexRole {
        var id: String
        var subshape: String
        var uIndex: Int
        var vIndex: Int
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
                surfaceControlPointDisplays: document.productMetadata.surfaceControlPointDisplays,
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
        surfaceControlPointDisplays: [SurfaceControlPointDisplayID: SurfaceControlPointDisplay],
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
                polySpline: polySpline,
                surfaceControlPointDisplays: surfaceControlPointDisplays,
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
        polySpline: PolySplineFeature,
        surfaceControlPointDisplays: [SurfaceControlPointDisplayID: SurfaceControlPointDisplay],
        topologyEntriesByPersistentName: [String: TopologySummaryResult.Entry]
    ) -> SurfaceSourceSummaryResult.Patch {
        let patchID = patchCandidate.patchID
        let sourceMesh = polySpline.sourceMesh
        let faceName = persistentName(
            featureID: featureID,
            subshape: "patch:\(patchID):face"
        )
        let facePersistentName = persistentNameString(faceName)
        let surfaceReference = SurfaceReference(faceName: faceName)
        let faceSelectionComponentID = topologyEntriesByPersistentName[facePersistentName]?.selectionComponentID
        let faceSelectionReference: SelectionReference? = topologyEntriesByPersistentName[facePersistentName] == nil
            ? nil
            : .surface(.whole(surfaceReference))
        let edgePersistentNames = edgeRoles.map {
            persistentNameString(persistentName(featureID: featureID, subshape: "patch:\(patchID):\($0.subshape)"))
        }
        .filter { topologyEntriesByPersistentName[$0] != nil }
        let trimSelectionReferences = edgeRoles.enumerated().compactMap { index, role -> SelectionReference? in
            let edgeName = persistentNameString(
                persistentName(featureID: featureID, subshape: "patch:\(patchID):\(role.subshape)")
            )
            guard topologyEntriesByPersistentName[edgeName] != nil else {
                return nil
            }
            return .surface(.trim(SurfaceTrimReference(
                surface: surfaceReference,
                loopIndex: 0,
                edgeIndex: index
            )))
        }
        let controlVertices = zip(vertexRoles, patchCandidate.boundaryVertexIndices).map { role, sourceVertexIndex in
            controlVertex(
                featureID: featureID,
                patchID: patchID,
                role: role,
                surfaceReference: surfaceReference,
                sourceVertexIndex: sourceVertexIndex,
                sourceMesh: sourceMesh,
                surfaceControlPointDisplays: surfaceControlPointDisplays
            )
        }
        let controlPoints = surfaceControlPoints(
            featureID: featureID,
            patchID: patchID,
            surfaceReference: surfaceReference,
            patchCandidate: patchCandidate,
            polySpline: polySpline,
            surfaceControlPointDisplays: surfaceControlPointDisplays
        )
        return SurfaceSourceSummaryResult.Patch(
            patchID: patchID,
            facePersistentName: topologyEntriesByPersistentName[facePersistentName]?.persistentName,
            faceSelectionComponentID: faceSelectionComponentID,
            faceSelectionReference: faceSelectionReference,
            uDomain: SurfaceSourceSummaryResult.ParameterRange(lowerBound: 0.0, upperBound: 1.0),
            vDomain: SurfaceSourceSummaryResult.ParameterRange(lowerBound: 0.0, upperBound: 1.0),
            basis: cubicBezierBasis(),
            controlVertices: controlVertices,
            controlPoints: controlPoints,
            trimLoops: [
                SurfaceSourceSummaryResult.TrimLoop(
                    role: "outer",
                    parameterAddresses: cornerParameterAddresses(surfaceReference: surfaceReference),
                    sourceVertexIndices: patchCandidate.boundaryVertexIndices,
                    edgePersistentNames: edgePersistentNames,
                    selectionReferences: trimSelectionReferences
                ),
            ],
            parameterAddresses: patchParameterAddresses(surfaceReference: surfaceReference)
        )
    }

    private func surfaceControlPoints(
        featureID: FeatureID,
        patchID: Int,
        surfaceReference: SurfaceReference,
        patchCandidate: PatchCandidate,
        polySpline: PolySplineFeature,
        surfaceControlPointDisplays: [SurfaceControlPointDisplayID: SurfaceControlPointDisplay]
    ) -> [SurfaceSourceSummaryResult.ControlPoint] {
        guard patchCandidate.boundaryVertexIndices.count == 4 else {
            return []
        }
        let points = patchCandidate.boundaryVertexIndices.compactMap { sourceVertexIndex -> Point3D? in
            guard polySpline.sourceMesh.positions.indices.contains(sourceVertexIndex) else {
                return nil
            }
            return polySpline.sourceMesh.positions[sourceVertexIndex]
        }
        guard points.count == 4 else {
            return []
        }
        let surface = BSplineSurface3D.cubicBezierPatch(
            bottomLeft: points[0],
            bottomRight: points[1],
            topRight: points[2],
            topLeft: points[3]
        )
        var controlPoints = surface.controlPoints
        for override in polySpline.controlPointOverrides where override.patchID == patchID {
            let address = override.address
            guard address.isStrictInterior,
                  controlPoints.indices.contains(address.vIndex),
                  controlPoints[address.vIndex].indices.contains(address.uIndex),
                  override.point.isFinite else {
                continue
            }
            controlPoints[address.vIndex][address.uIndex] = override.point
        }

        var result: [SurfaceSourceSummaryResult.ControlPoint] = []
        result.reserveCapacity(16)
        for vIndex in 0..<controlPoints.count {
            for uIndex in 0..<controlPoints[vIndex].count {
                let point = controlPoints[vIndex][uIndex]
                let isBoundary = uIndex == 0 || uIndex == 3 || vIndex == 0 || vIndex == 3
                let isCorner = (uIndex == 0 || uIndex == 3) && (vIndex == 0 || vIndex == 3)
                let selectionReference = SelectionReference.surface(.controlPoint(SurfaceControlPointReference(
                    surface: surfaceReference,
                    uIndex: uIndex,
                    vIndex: vIndex
                )))
                result.append(SurfaceSourceSummaryResult.ControlPoint(
                    id: "feature:\(featureID.description)/patch:\(patchID)/surfaceControlPoint:u\(uIndex):v\(vIndex)",
                    uIndex: uIndex,
                    vIndex: vIndex,
                    point: SurfaceSourceSummaryResult.Point(x: point.x, y: point.y, z: point.z),
                    isBoundary: isBoundary,
                    isEditable: isBoundary == false || isCorner,
                    selectionReference: selectionReference,
                    isPointDisplayVisible: isSurfaceControlPointDisplayVisible(
                        selectionReference,
                        in: surfaceControlPointDisplays
                    )
                ))
            }
        }
        return result
    }

    private func controlVertex(
        featureID: FeatureID,
        patchID: Int,
        role: SurfaceVertexRole,
        surfaceReference: SurfaceReference,
        sourceVertexIndex: Int,
        sourceMesh: Mesh,
        surfaceControlPointDisplays: [SurfaceControlPointDisplayID: SurfaceControlPointDisplay]
    ) -> SurfaceSourceSummaryResult.ControlVertex {
        let generatedVertexName = persistentName(
            featureID: featureID,
            subshape: "patch:\(patchID):\(role.subshape)"
        )
        let generatedVertexPersistentName = persistentNameString(generatedVertexName)
        let point: Point3D
        if sourceMesh.positions.indices.contains(sourceVertexIndex) {
            point = sourceMesh.positions[sourceVertexIndex]
        } else {
            point = Point3D(x: 0.0, y: 0.0, z: 0.0)
        }
        let selectionReference = SelectionReference.surface(.controlPoint(SurfaceControlPointReference(
            surface: surfaceReference,
            uIndex: role.uIndex,
            vIndex: role.vIndex
        )))
        return SurfaceSourceSummaryResult.ControlVertex(
            id: "feature:\(featureID.description)/patch:\(patchID)/cv:\(role.id)",
            role: role.id,
            sourceVertexIndex: sourceVertexIndex,
            point: SurfaceSourceSummaryResult.Point(x: point.x, y: point.y, z: point.z),
            generatedVertexPersistentName: generatedVertexPersistentName,
            selectionComponentID: SelectionComponentID
                .generatedTopology(generatedVertexPersistentName)
                .rawValue,
            selectionReference: selectionReference,
            isPointDisplayVisible: isSurfaceControlPointDisplayVisible(
                selectionReference,
                in: surfaceControlPointDisplays
            )
        )
    }

    private func isSurfaceControlPointDisplayVisible(
        _ selectionReference: SelectionReference,
        in displays: [SurfaceControlPointDisplayID: SurfaceControlPointDisplay]
    ) -> Bool {
        let id: SurfaceControlPointDisplayID
        do {
            id = try SurfaceControlPointDisplayID(selectionReference: selectionReference)
        } catch {
            return false
        }
        return displays[id]?.isVisible == true
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
            return topologyEntriesByPersistentName[persistentNameString(candidateName)]?.persistentName
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
            controlPointCount: sources.reduce(0) { partial, source in
                partial + source.patches.reduce(0) { $0 + $1.controlPoints.count }
            },
            trimLoopCount: sources.reduce(0) { partial, source in
                partial + source.patches.reduce(0) { $0 + $1.trimLoops.count }
            },
            adjacencyCount: sources.reduce(0) { $0 + $1.adjacencies.count }
        )
    }

    private func persistentName(featureID: FeatureID, subshape: String) -> PersistentName {
        PersistentName(components: [
            .feature(featureID),
            .generated("polySpline"),
            .subshape(subshape),
        ])
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

    private func patchParameterAddresses(
        surfaceReference: SurfaceReference
    ) -> [SurfaceSourceSummaryResult.ParameterAddress] {
        cornerParameterAddresses(surfaceReference: surfaceReference) + [
            SurfaceSourceSummaryResult.ParameterAddress(
                id: "center",
                u: 0.5,
                v: 0.5,
                selectionReference: .surface(.parameter(SurfaceParameterReference(
                    surface: surfaceReference,
                    u: 0.5,
                    v: 0.5
                )))
            ),
        ]
    }

    private func cornerParameterAddresses(
        surfaceReference: SurfaceReference
    ) -> [SurfaceSourceSummaryResult.ParameterAddress] {
        [
            SurfaceSourceSummaryResult.ParameterAddress(
                id: "uMin:vMin",
                u: 0.0,
                v: 0.0,
                selectionReference: .surface(.parameter(SurfaceParameterReference(
                    surface: surfaceReference,
                    u: 0.0,
                    v: 0.0
                )))
            ),
            SurfaceSourceSummaryResult.ParameterAddress(
                id: "uMax:vMin",
                u: 1.0,
                v: 0.0,
                selectionReference: .surface(.parameter(SurfaceParameterReference(
                    surface: surfaceReference,
                    u: 1.0,
                    v: 0.0
                )))
            ),
            SurfaceSourceSummaryResult.ParameterAddress(
                id: "uMax:vMax",
                u: 1.0,
                v: 1.0,
                selectionReference: .surface(.parameter(SurfaceParameterReference(
                    surface: surfaceReference,
                    u: 1.0,
                    v: 1.0
                )))
            ),
            SurfaceSourceSummaryResult.ParameterAddress(
                id: "uMin:vMax",
                u: 0.0,
                v: 1.0,
                selectionReference: .surface(.parameter(SurfaceParameterReference(
                    surface: surfaceReference,
                    u: 0.0,
                    v: 1.0
                )))
            ),
        ]
    }

    private var vertexRoles: [SurfaceVertexRole] {
        [
            SurfaceVertexRole(id: "uMin:vMin", subshape: "vertex:uMin:vMin", uIndex: 0, vIndex: 0),
            SurfaceVertexRole(id: "uMax:vMin", subshape: "vertex:uMax:vMin", uIndex: 3, vIndex: 0),
            SurfaceVertexRole(id: "uMax:vMax", subshape: "vertex:uMax:vMax", uIndex: 3, vIndex: 3),
            SurfaceVertexRole(id: "uMin:vMax", subshape: "vertex:uMin:vMax", uIndex: 0, vIndex: 3),
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
