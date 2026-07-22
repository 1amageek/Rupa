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

    private struct PatchSummaryBuildResult {
        var patch: SurfaceSourceSummaryResult.Patch
        var diagnostics: [SurfaceSourceSummaryResult.Diagnostic]
    }

    private struct SurfaceVertexRole {
        var id: String
        var subshape: String
        var uIndex: Int
        var vIndex: Int
    }

    public func summarize(
        document: DesignDocument,
        displayUnit: LengthDisplayUnit,
        surfaceControlPointDisplays: [SurfaceControlPointDisplayID: SurfaceControlPointDisplay] = [:],
        surfaceFrameDisplays: [SurfaceFrameDisplayID: SurfaceFrameDisplay] = [:],
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
        var sources: [SurfaceSourceSummaryResult.Source] = []
        for featureID in document.cadDocument.designGraph.order {
            guard let feature = document.cadDocument.designGraph.nodes[featureID],
                  feature.isSuppressed == false else {
                continue
            }
            switch feature.operation {
            case let .polySpline(polySpline):
                sources.append(try source(
                    featureID: featureID,
                    feature: feature,
                    polySpline: polySpline,
                    sceneNodeID: sceneNodeIDsByFeatureID[featureID],
                    surfaceControlPointDisplays: surfaceControlPointDisplays,
                    surfaceFrameDisplays: surfaceFrameDisplays,
                    topologyEntriesByPersistentName: topologyEntriesByPersistentName,
                    tolerance: document.modelingSettings.tolerance
                ))
            case let .bSplineSurface(surfaceFeature):
                if let surfaceSource = try BSplineSurfaceSourceSummaryBuilder().source(
                    featureID: featureID,
                    feature: feature,
                    surfaceFeature: surfaceFeature,
                    sceneNodeID: sceneNodeIDsByFeatureID[featureID],
                    surfaceControlPointDisplays: surfaceControlPointDisplays,
                    surfaceFrameDisplays: surfaceFrameDisplays,
                    topologyEntriesByPersistentName: topologyEntriesByPersistentName,
                    tolerance: document.modelingSettings.tolerance
                ) {
                    sources.append(surfaceSource)
                }
            default:
                continue
            }
        }

        return SurfaceSourceSummaryResult(
            displayUnit: displayUnit,
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
        surfaceFrameDisplays: [SurfaceFrameDisplayID: SurfaceFrameDisplay],
        topologyEntriesByPersistentName: [String: TopologySummaryResult.Entry],
        tolerance: ModelingTolerance
    ) throws -> SurfaceSourceSummaryResult.Source {
        let analysis = PolySplineMeshAnalysisService().analyze(
            sourceMesh: polySpline.sourceMesh,
            options: polySpline.options,
            tolerance: tolerance
        )
        let patchCandidates = selectedPatchCandidates(
            from: analysis,
            sourceMesh: polySpline.sourceMesh
        )
        let patchResults = try patchCandidates.map { patchCandidate in
            try patch(
                featureID: featureID,
                patchCandidate: patchCandidate,
                polySpline: polySpline,
                surfaceControlPointDisplays: surfaceControlPointDisplays,
                surfaceFrameDisplays: surfaceFrameDisplays,
                topologyEntriesByPersistentName: topologyEntriesByPersistentName
            )
        }
        let patches = patchResults.map(\.patch)
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
            } + patchResults.flatMap(\.diagnostics)
        )
    }

    private func patch(
        featureID: FeatureID,
        patchCandidate: PatchCandidate,
        polySpline: PolySplineFeature,
        surfaceControlPointDisplays: [SurfaceControlPointDisplayID: SurfaceControlPointDisplay],
        surfaceFrameDisplays: [SurfaceFrameDisplayID: SurfaceFrameDisplay],
        topologyEntriesByPersistentName: [String: TopologySummaryResult.Entry]
    ) throws -> PatchSummaryBuildResult {
        let patchID = patchCandidate.patchID
        let sourceMesh = polySpline.sourceMesh
        let faceSubshapeID = subshapeID(
            featureID: featureID,
            subshape: "patch:\(patchID):face"
        )
        let faceIdentityKey = stableSubshapeKey(faceSubshapeID)
        guard let faceEntry = topologyEntriesByPersistentName[faceIdentityKey] else {
            throw EditorError(
                code: .referenceUnresolved,
                message: "Surface source summary requires current stable PolySpline face topology."
            )
        }
        let surfaceReference = SurfaceReference(subshape: faceEntry.stableReference)
        let faceSelectionComponentID = faceEntry.selectionComponentID
        let faceSelectionReference: SelectionReference? = .surface(.whole(surfaceReference))
        let edgePersistentNames = edgeRoles.map {
            stableSubshapeKey(subshapeID(
                featureID: featureID,
                subshape: "patch:\(patchID):\($0.subshape)"
            ))
        }
        .filter { topologyEntriesByPersistentName[$0] != nil }
        let trimSelectionReferences = edgeRoles.enumerated().compactMap { index, role -> SelectionReference? in
            let edgeName = stableSubshapeKey(
                subshapeID(featureID: featureID, subshape: "patch:\(patchID):\(role.subshape)")
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
        let controlVertices = try zip(vertexRoles, patchCandidate.boundaryVertexIndices).map { role, sourceVertexIndex in
            try controlVertex(
                featureID: featureID,
                patchID: patchID,
                role: role,
                surfaceReference: surfaceReference,
                sourceVertexIndex: sourceVertexIndex,
                sourceMesh: sourceMesh,
                surfaceControlPointDisplays: surfaceControlPointDisplays,
                topologyEntriesByPersistentName: topologyEntriesByPersistentName
            )
        }
        let patchSurface = polySplinePatchSurface(
            patchCandidate: patchCandidate,
            polySpline: polySpline
        )
        let trimEdges = trimEdges(
            featureID: featureID,
            patchID: patchID,
            surfaceReference: surfaceReference,
            surface: patchSurface,
            topologyEntriesByPersistentName: topologyEntriesByPersistentName
        )
        let controlPoints = surfaceControlPoints(
            featureID: featureID,
            patchID: patchID,
            surfaceReference: surfaceReference,
            surface: patchSurface,
            surfaceControlPointDisplays: surfaceControlPointDisplays
        )
        let basis = cubicBezierBasis(isRational: isRationalPatch(polySpline: polySpline, patchID: patchID))
        let frameSampleResult: SurfaceSourceFrameSampleBuilder.Result
        if let patchSurface {
            frameSampleResult = SurfaceSourceFrameSampleBuilder().buildSamples(
                featureID: featureID,
                patchID: patchID,
                surface: patchSurface,
                surfaceReference: surfaceReference,
                uSpans: basis.uSpans,
                vSpans: basis.vSpans,
                surfaceFrameDisplays: surfaceFrameDisplays
            )
        } else {
            frameSampleResult = SurfaceSourceFrameSampleBuilder.Result()
        }

        return PatchSummaryBuildResult(patch: SurfaceSourceSummaryResult.Patch(
            patchID: patchID,
            facePersistentName: faceIdentityKey,
            faceSelectionComponentID: faceSelectionComponentID,
            faceSelectionReference: faceSelectionReference,
            uDomain: SurfaceSourceSummaryResult.ParameterRange(lowerBound: 0.0, upperBound: 1.0),
            vDomain: SurfaceSourceSummaryResult.ParameterRange(lowerBound: 0.0, upperBound: 1.0),
            basis: basis,
            controlVertices: controlVertices,
            controlPoints: controlPoints,
            trimLoops: [
                SurfaceSourceSummaryResult.TrimLoop(
                    role: "outer",
                    parameterAddresses: cornerParameterAddresses(surfaceReference: surfaceReference),
                    sourceVertexIndices: patchCandidate.boundaryVertexIndices,
                    edgePersistentNames: edgePersistentNames,
                    selectionReferences: trimSelectionReferences,
                    edges: trimEdges
                ),
            ],
            frameSamples: frameSampleResult.samples,
            parameterAddresses: patchParameterAddresses(surfaceReference: surfaceReference)
        ), diagnostics: frameSampleResult.diagnostics)
    }

    private func trimEdges(
        featureID: FeatureID,
        patchID: Int,
        surfaceReference: SurfaceReference,
        surface: BSplineSurface3D?,
        topologyEntriesByPersistentName: [String: TopologySummaryResult.Entry]
    ) -> [SurfaceSourceSummaryResult.TrimLoop.Edge] {
        BSplineSurfaceBoundarySide.allCases.enumerated().map { index, side in
            let edgePersistentName = stableSubshapeKey(
                subshapeID(featureID: featureID, subshape: "patch:\(patchID):edge:\(side.rawValue)")
            )
            let selectionReference: SelectionReference? = topologyEntriesByPersistentName[edgePersistentName] == nil
                ? nil
                : .surface(.trim(SurfaceTrimReference(
                    surface: surfaceReference,
                    loopIndex: 0,
                    edgeIndex: index
                )))
            let parameters = trimEdgeParameters(side: side, surfaceReference: surfaceReference)
            return SurfaceSourceSummaryResult.TrimLoop.Edge(
                index: index,
                role: side.rawValue,
                persistentName: edgePersistentName,
                selectionReference: selectionReference,
                startParameter: parameters.start,
                endParameter: parameters.end,
                boundaryDirection: side.boundaryDirection,
                inwardDirection: side.inwardDirection,
                boundaryControlPointReferences: surface.map {
                    controlPointReferences(
                        side: side,
                        inwardOffset: 0,
                        surface: $0,
                        surfaceReference: surfaceReference
                    )
                } ?? [],
                firstInwardControlPointReferences: surface.map {
                    controlPointReferences(
                        side: side,
                        inwardOffset: 1,
                        surface: $0,
                        surfaceReference: surfaceReference
                    )
                } ?? [],
                secondInwardControlPointReferences: surface.map {
                    controlPointReferences(
                        side: side,
                        inwardOffset: 2,
                        surface: $0,
                        surfaceReference: surfaceReference
                    )
                } ?? [],
                supportedBoundaryContinuityLevels: [],
                supportsBoundaryContinuityMatching: false,
                unsupportedReason: "PolySpline trim continuity mutation is not implemented; use surface continuity diagnostics or direct B-spline boundary matching."
            )
        }
    }

    private func trimEdgeParameters(
        side: BSplineSurfaceBoundarySide,
        surfaceReference: SurfaceReference
    ) -> (start: SurfaceSourceSummaryResult.ParameterAddress, end: SurfaceSourceSummaryResult.ParameterAddress) {
        switch side {
        case .vMin:
            return (
                parameterAddress(id: "uMin:vMin", surfaceReference: surfaceReference, u: 0.0, v: 0.0),
                parameterAddress(id: "uMax:vMin", surfaceReference: surfaceReference, u: 1.0, v: 0.0)
            )
        case .uMax:
            return (
                parameterAddress(id: "uMax:vMin", surfaceReference: surfaceReference, u: 1.0, v: 0.0),
                parameterAddress(id: "uMax:vMax", surfaceReference: surfaceReference, u: 1.0, v: 1.0)
            )
        case .vMax:
            return (
                parameterAddress(id: "uMax:vMax", surfaceReference: surfaceReference, u: 1.0, v: 1.0),
                parameterAddress(id: "uMin:vMax", surfaceReference: surfaceReference, u: 0.0, v: 1.0)
            )
        case .uMin:
            return (
                parameterAddress(id: "uMin:vMax", surfaceReference: surfaceReference, u: 0.0, v: 1.0),
                parameterAddress(id: "uMin:vMin", surfaceReference: surfaceReference, u: 0.0, v: 0.0)
            )
        }
    }

    private func controlPointReferences(
        side: BSplineSurfaceBoundarySide,
        inwardOffset: Int,
        surface: BSplineSurface3D,
        surfaceReference: SurfaceReference
    ) -> [SelectionReference] {
        guard inwardOffset < inwardControlPointCount(for: side, in: surface) else {
            return []
        }
        return boundaryOrdinals(for: side, in: surface).map { ordinal in
            let indices = controlPointIndices(side: side, ordinal: ordinal, inwardOffset: inwardOffset, surface: surface)
            return .surface(.controlPoint(SurfaceControlPointReference(
                surface: surfaceReference,
                uIndex: indices.uIndex,
                vIndex: indices.vIndex
            )))
        }
    }

    private func boundaryOrdinals(
        for side: BSplineSurfaceBoundarySide,
        in surface: BSplineSurface3D
    ) -> [Int] {
        switch side {
        case .vMin:
            return Array(0..<surface.uControlPointCount)
        case .uMax:
            return Array(0..<surface.vControlPointCount)
        case .vMax:
            return Array((0..<surface.uControlPointCount).reversed())
        case .uMin:
            return Array((0..<surface.vControlPointCount).reversed())
        }
    }

    private func controlPointIndices(
        side: BSplineSurfaceBoundarySide,
        ordinal: Int,
        inwardOffset: Int,
        surface: BSplineSurface3D
    ) -> (uIndex: Int, vIndex: Int) {
        switch side {
        case .vMin, .vMax:
            return (uIndex: ordinal, vIndex: side.inwardIndex(offset: inwardOffset, in: surface))
        case .uMin, .uMax:
            return (uIndex: side.inwardIndex(offset: inwardOffset, in: surface), vIndex: ordinal)
        }
    }

    private func inwardControlPointCount(
        for side: BSplineSurfaceBoundarySide,
        in surface: BSplineSurface3D
    ) -> Int {
        switch side.inwardDirection {
        case .u:
            return surface.uControlPointCount
        case .v:
            return surface.vControlPointCount
        }
    }

    private func surfaceControlPoints(
        featureID: FeatureID,
        patchID: Int,
        surfaceReference: SurfaceReference,
        surface: BSplineSurface3D?,
        surfaceControlPointDisplays: [SurfaceControlPointDisplayID: SurfaceControlPointDisplay]
    ) -> [SurfaceSourceSummaryResult.ControlPoint] {
        guard let surface else {
            return []
        }
        let controlPoints = surface.controlPoints

        var result: [SurfaceSourceSummaryResult.ControlPoint] = []
        result.reserveCapacity(16)
        for vIndex in 0..<controlPoints.count {
            for uIndex in 0..<controlPoints[vIndex].count {
                let point = controlPoints[vIndex][uIndex]
                let weight = surface.weights.indices.contains(vIndex)
                    && surface.weights[vIndex].indices.contains(uIndex)
                    ? surface.weights[vIndex][uIndex]
                    : 1.0
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
                    weight: weight,
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

    private func polySplinePatchSurface(
        patchCandidate: PatchCandidate,
        polySpline: PolySplineFeature
    ) -> BSplineSurface3D? {
        guard patchCandidate.boundaryVertexIndices.count == 4 else {
            return nil
        }
        let points = patchCandidate.boundaryVertexIndices.compactMap { sourceVertexIndex -> Point3D? in
            guard polySpline.sourceMesh.positions.indices.contains(sourceVertexIndex) else {
                return nil
            }
            return polySpline.sourceMesh.positions[sourceVertexIndex]
        }
        guard points.count == 4 else {
            return nil
        }
        var surface = BSplineSurface3D.cubicBezierPatch(
            bottomLeft: points[0],
            bottomRight: points[1],
            topRight: points[2],
            topLeft: points[3]
        )
        for override in polySpline.controlPointOverrides where override.patchID == patchCandidate.patchID {
            let address = override.address
            guard address.isStrictInterior,
                  surface.controlPoints.indices.contains(address.vIndex),
                  surface.controlPoints[address.vIndex].indices.contains(address.uIndex),
                  surface.weights.indices.contains(address.vIndex),
                  surface.weights[address.vIndex].indices.contains(address.uIndex),
                  override.point.isFinite else {
                continue
            }
            surface.controlPoints[address.vIndex][address.uIndex] = override.point
            surface.weights[address.vIndex][address.uIndex] = override.weight
        }
        return surface
    }

    private func controlVertex(
        featureID: FeatureID,
        patchID: Int,
        role: SurfaceVertexRole,
        surfaceReference: SurfaceReference,
        sourceVertexIndex: Int,
        sourceMesh: Mesh,
        surfaceControlPointDisplays: [SurfaceControlPointDisplayID: SurfaceControlPointDisplay],
        topologyEntriesByPersistentName: [String: TopologySummaryResult.Entry]
    ) throws -> SurfaceSourceSummaryResult.ControlVertex {
        let generatedVertexSubshapeID = subshapeID(
            featureID: featureID,
            subshape: "patch:\(patchID):\(role.subshape)"
        )
        let generatedVertexIdentityKey = stableSubshapeKey(generatedVertexSubshapeID)
        guard let vertexEntry = topologyEntriesByPersistentName[generatedVertexIdentityKey] else {
            throw EditorError(
                code: .referenceUnresolved,
                message: "Surface source summary requires current stable PolySpline vertex topology."
            )
        }
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
            generatedVertexPersistentName: generatedVertexIdentityKey,
            selectionComponentID: try SelectionComponentID
                .stableTopology(vertexEntry.stableReference)
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
            let candidateSubshapeID = subshapeID(
                featureID: featureID,
                subshape: "patch:\(adjacency.firstCandidateID):\(edgeRoles[index].subshape)"
            )
            return topologyEntriesByPersistentName[stableSubshapeKey(candidateSubshapeID)]
                .map { stableSubshapeKey($0.stableReference.subshapeID) }
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
        let summary = try TopologySnapshotService(pipeline: pipelineOverride).snapshot(
            document: document,
            objectRegistry: objectRegistry,
            currentEvaluation: currentEvaluation,
            currentGeneration: currentGeneration
        )
        return Dictionary(uniqueKeysWithValues: summary.entries.map {
            (stableSubshapeKey($0.stableReference.subshapeID), $0)
        })
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
            frameSampleCount: sources.reduce(0) { partial, source in
                partial + source.patches.reduce(0) { $0 + $1.frameSamples.count }
            },
            trimLoopCount: sources.reduce(0) { partial, source in
                partial + source.patches.reduce(0) { $0 + $1.trimLoops.count }
            },
            adjacencyCount: sources.reduce(0) { $0 + $1.adjacencies.count }
        )
    }

    private func parameterAddress(
        id: String,
        surfaceReference: SurfaceReference,
        u: Double,
        v: Double
    ) -> SurfaceSourceSummaryResult.ParameterAddress {
        SurfaceSourceSummaryResult.ParameterAddress(
            id: id,
            u: u,
            v: v,
            selectionReference: .surface(.parameter(SurfaceParameterReference(
                surface: surfaceReference,
                u: u,
                v: v
            )))
        )
    }

    private func subshapeID(
        featureID: FeatureID,
        generatedRole: String = "polySpline",
        subshape: String
    ) -> SubshapeID {
        SubshapeID(
            featureID: featureID,
            role: "\(generatedRole).\(subshape)",
            ordinal: 0
        )
    }

    private func stableSubshapeKey(_ subshapeID: SubshapeID) -> String {
        "feature:\(subshapeID.featureID.description)/role:\(subshapeID.role)/ordinal:\(subshapeID.ordinal)"
    }

    private func isRationalPatch(
        polySpline: PolySplineFeature,
        patchID: Int
    ) -> Bool {
        polySpline.controlPointOverrides.contains { override in
            override.patchID == patchID && abs(override.weight - 1.0) > 1.0e-12
        }
    }

    private func cubicBezierBasis(isRational: Bool = false) -> SurfaceSourceSummaryResult.Basis {
        let uKnots = [0.0, 0.0, 0.0, 0.0, 1.0, 1.0, 1.0, 1.0]
        let vKnots = [0.0, 0.0, 0.0, 0.0, 1.0, 1.0, 1.0, 1.0]
        return SurfaceSourceSummaryResult.Basis(
            kind: "cubicBezierBSpline",
            uDegree: 3,
            vDegree: 3,
            uOrder: 4,
            vOrder: 4,
            uKnots: uKnots,
            vKnots: vKnots,
            uKnotVector: knotVector(axis: "u", knots: uKnots),
            vKnotVector: knotVector(axis: "v", knots: vKnots),
            uSpans: spans(axis: "u", knots: uKnots),
            vSpans: spans(axis: "v", knots: vKnots),
            uSpanCount: 1,
            vSpanCount: 1,
            isRational: isRational
        )
    }

    private func knotVector(
        axis: String,
        knots: [Double]
    ) -> [SurfaceSourceSummaryResult.Basis.Knot] {
        let lowerBound = knots.first
        let upperBound = knots.last
        let multiplicities = Dictionary(grouping: knots, by: { $0 }).mapValues(\.count)
        return knots.indices.map { index in
            let value = knots[index]
            return SurfaceSourceSummaryResult.Basis.Knot(
                id: "\(axis)Knot:\(index)",
                index: index,
                value: value,
                multiplicity: multiplicities[value] ?? 1,
                isBoundary: value == lowerBound || value == upperBound
            )
        }
    }

    private func spans(
        axis: String,
        knots: [Double]
    ) -> [SurfaceSourceSummaryResult.Basis.Span] {
        guard knots.count >= 2 else {
            return []
        }
        var result: [SurfaceSourceSummaryResult.Basis.Span] = []
        for index in 0..<(knots.count - 1) {
            let lowerBound = knots[index]
            let upperBound = knots[index + 1]
            guard upperBound > lowerBound else {
                continue
            }
            result.append(SurfaceSourceSummaryResult.Basis.Span(
                id: "\(axis)Span:\(result.count)",
                index: result.count,
                lowerBound: lowerBound,
                upperBound: upperBound,
                startKnotIndex: index,
                endKnotIndex: index + 1
            ))
        }
        return result
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
