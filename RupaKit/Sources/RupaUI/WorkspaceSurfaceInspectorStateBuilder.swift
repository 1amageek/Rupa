import RupaCore

struct WorkspaceSurfaceInspectorStateBuilder {
    var document: DesignDocument
    var selection: SelectionModel
    var currentEvaluation: DocumentEvaluationContext?
    var documentGeneration: DocumentGeneration
    var objectRegistry: ObjectTypeRegistry
    var surfaceAnalysisOptions: SurfaceAnalysisOptions

    var surfaceControlPointReferences: [SelectionReference] {
        selection.selectedReferences.filter { reference in
            if case .surface(.controlPoint) = reference {
                return true
            }
            return false
        }
    }

    var surfaceParameterReferences: [SelectionReference] {
        selection.selectedReferences.filter { reference in
            switch reference {
            case .surface(.parameter), .surface(.knot), .surface(.span):
                return true
            default:
                return false
            }
        }
    }

    func surfaceControlPointStateResult() -> Result<SurfaceControlPointInspectorState?, Error> {
        guard !surfaceControlPointReferences.isEmpty else {
            return .success(nil)
        }
        do {
            let summary = try SurfaceSourceSummaryService().summarize(document: document)
            guard let state = SurfaceControlPointInspectorState(
                selectedReferences: surfaceControlPointReferences,
                summaryResult: summary,
                surfaceFrameDisplays: document.productMetadata.surfaceFrameDisplays
            ) else {
                throw EditorError(
                    code: .referenceUnresolved,
                    message: "Selected surface control point references could not be resolved in the current surface source summary."
                )
            }
            return .success(try resolveFrames(for: state))
        } catch {
            return .failure(error)
        }
    }

    func surfaceParameterStateResult() -> Result<SurfaceParameterInspectorState?, Error> {
        guard !surfaceParameterReferences.isEmpty else {
            return .success(nil)
        }
        do {
            let summary = try SurfaceSourceSummaryService().summarize(document: document)
            guard let state = SurfaceParameterInspectorState(
                selectedReferences: surfaceParameterReferences,
                summaryResult: summary,
                surfaceFrameDisplays: document.productMetadata.surfaceFrameDisplays
            ) else {
                throw EditorError(
                    code: .referenceUnresolved,
                    message: "Selected surface parameter references could not be resolved in the current surface source summary."
                )
            }
            return .success(try resolveFrames(for: state))
        } catch {
            return .failure(error)
        }
    }

    func analysisSummary(for nodes: [SceneNode]) -> SurfaceAnalysisResult? {
        switch analysisSummaryResult(for: nodes) {
        case .success(let summary):
            return summary
        case .failure:
            return nil
        }
    }

    func continuitySummary(for nodes: [SceneNode]) -> RupaCore.SurfaceContinuityResult? {
        switch continuitySummaryResult(for: nodes) {
        case .success(let summary):
            return summary
        case .failure:
            return nil
        }
    }

    func analysisSummaryResult(for nodes: [SceneNode]) -> Result<SurfaceAnalysisResult?, Error> {
        do {
            return .success(try resolveAnalysisSummary(for: nodes))
        } catch {
            return .failure(error)
        }
    }

    func analysisResult(for nodes: [SceneNode]) -> Result<InspectorSurfaceAnalysis?, Error> {
        do {
            return .success(try resolveAnalysis(for: nodes))
        } catch {
            return .failure(error)
        }
    }

    func continuitySummaryResult(for nodes: [SceneNode]) -> Result<RupaCore.SurfaceContinuityResult?, Error> {
        do {
            return .success(try resolveContinuitySummary(for: nodes))
        } catch {
            return .failure(error)
        }
    }

    func continuityResult(for nodes: [SceneNode]) -> Result<InspectorSurfaceContinuity?, Error> {
        do {
            return .success(try resolveContinuity(for: nodes))
        } catch {
            return .failure(error)
        }
    }

    func showsContinuitySection(for nodes: [SceneNode]) -> Bool {
        guard nodes.count == 1, let node = nodes.first else {
            return false
        }
        return node.object?.geometryRole == .surface
            || !generatedTopologyPersistentNames().isEmpty
    }

    func generatedTopologyPersistentNames() -> Set<String> {
        var names = Set<String>()
        for target in selection.selectedTargets {
            let componentID: SelectionComponentID?
            switch target.component {
            case .object, .sketchEntity, .region, .vertex:
                componentID = nil
            case .face(let id), .edge(let id):
                componentID = id
            }
            guard let name = componentID?.generatedTopologyPersistentName else {
                continue
            }
            names.insert(name)
        }
        return names
    }

    private func resolveAnalysis(for nodes: [SceneNode]) throws -> InspectorSurfaceAnalysis? {
        guard let result = try resolveAnalysisSummary(for: nodes) else {
            return nil
        }
        let faces = selectedAnalysisFaces(result.faces, nodes: nodes)
        return InspectorSurfaceAnalysis(
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
            },
            faces: faces.map { face in
                InspectorSurfaceFaceAnalysis(
                    id: face.faceID,
                    facePersistentNames: face.facePersistentNames,
                    uDegree: face.uDegree,
                    vDegree: face.vDegree,
                    uControlPointCount: face.uControlPointCount,
                    vControlPointCount: face.vControlPointCount,
                    sampleCount: face.samples.count,
                    trimBoundaryCount: face.trimBoundaries.count,
                    innerTrimBoundaryCount: face.trimBoundaries.filter { $0.role == .inner }.count,
                    openTrimBoundaryCount: face.trimBoundaries.filter { !$0.isClosed }.count,
                    trimBoundaryEdgeCount: face.trimBoundaries.reduce(0) { partial, boundary in
                        partial + boundary.edgeCount
                    },
                    trimBoundaryLength: face.trimBoundaries.reduce(0.0) { partial, boundary in
                        partial + boundary.estimatedLength
                    },
                    maxUNormalChangePerLength: face.maxUNormalChangePerLength,
                    maxVNormalChangePerLength: face.maxVNormalChangePerLength,
                    maxNormalAngle: face.maxNormalAngle,
                    maxAbsUNormalCurvature: face.maxAbsUNormalCurvature,
                    maxAbsVNormalCurvature: face.maxAbsVNormalCurvature,
                    maxAbsPrincipalCurvature: face.maxAbsPrincipalCurvature,
                    maxAbsGaussianCurvature: face.maxAbsGaussianCurvature,
                    minimumPrincipalDirection: face.samples.first?.minimumPrincipalDirection,
                    maximumPrincipalDirection: face.samples.first?.maximumPrincipalDirection
                )
            },
            diagnostics: result.diagnostics
        )
    }

    private func resolveFrames(
        for state: SurfaceParameterInspectorState
    ) throws -> SurfaceParameterInspectorState {
        let referenceQueries = state.entries.compactMap { entry -> (SelectionReference, SurfaceFrameQuery)? in
            guard let frameQuery = entry.frameQuery else {
                return nil
            }
            return (entry.selectionReference, frameQuery)
        }
        return state.resolvingFrames(try resolvedFrameMap(for: referenceQueries))
    }

    private func resolveFrames(
        for state: SurfaceControlPointInspectorState
    ) throws -> SurfaceControlPointInspectorState {
        let referenceQueries = state.selectedReferences.map { reference in
            (reference, SurfaceFrameQuery(selectionReference: reference))
        }
        return state.resolvingFrames(try resolvedFrameMap(for: referenceQueries))
    }

    private func resolvedFrameMap(
        for referenceQueries: [(SelectionReference, SurfaceFrameQuery)]
    ) throws -> [SelectionReference: SurfaceFrameResult.Frame] {
        guard !referenceQueries.isEmpty else {
            return [:]
        }
        let frameResult = try SurfaceFrameService().resolve(
            document: document,
            queries: referenceQueries.map(\.1),
            objectRegistry: objectRegistry,
            currentEvaluation: currentEvaluation,
            currentGeneration: documentGeneration
        )
        var framesByReference: [SelectionReference: SurfaceFrameResult.Frame] = [:]
        for (index, frame) in frameResult.frames.enumerated() where referenceQueries.indices.contains(index) {
            framesByReference[referenceQueries[index].0] = frame
        }
        return framesByReference
    }

    private func resolveAnalysisSummary(for nodes: [SceneNode]) throws -> SurfaceAnalysisResult? {
        guard nodes.count == 1, let node = nodes.first else {
            return nil
        }
        let selectedPersistentNames = generatedTopologyPersistentNames()
        guard !selectedPersistentNames.isEmpty || node.object?.geometryRole == .surface else {
            return nil
        }

        let result = try SurfaceAnalysisService(options: surfaceAnalysisOptions).analyze(
            document: document,
            objectRegistry: objectRegistry,
            currentEvaluation: currentEvaluation,
            currentGeneration: documentGeneration
        )
        guard result.counts.bSplineFaceCount > 0 else {
            return nil
        }
        return result
    }

    private func selectedAnalysisFaces(
        _ faces: [SurfaceAnalysisResult.FaceAnalysis],
        nodes: [SceneNode]
    ) -> [SurfaceAnalysisResult.FaceAnalysis] {
        let selectedPersistentNames = generatedTopologyPersistentNames()
        if !selectedPersistentNames.isEmpty {
            return faces.filter { face in
                analysisFace(face, containsAny: selectedPersistentNames)
            }
        }
        let selectedFeatureIDs = Set(
            nodes.compactMap { node -> String? in
                guard node.reference?.kind == .body else {
                    return nil
                }
                return node.reference?.featureID?.description
            }
        )
        guard !selectedFeatureIDs.isEmpty else {
            return []
        }
        return faces.filter { face in
            guard let sourceFeatureID = face.sourceFeatureID else {
                return false
            }
            return selectedFeatureIDs.contains(sourceFeatureID)
        }
    }

    private func resolveContinuity(for nodes: [SceneNode]) throws -> InspectorSurfaceContinuity? {
        guard let result = try resolveContinuitySummary(for: nodes) else {
            return nil
        }
        let selectedPersistentNames = generatedTopologyPersistentNames()
        let adjacencies: [RupaCore.SurfaceContinuityResult.Adjacency]
        if selectedPersistentNames.isEmpty {
            adjacencies = result.adjacencies
        } else {
            adjacencies = result.adjacencies.filter { adjacency in
                surfaceAdjacency(adjacency, containsAny: selectedPersistentNames)
            }
        }
        return InspectorSurfaceContinuity(
            bSplineFaceCount: result.counts.bSplineFaceCount,
            sharedEdgeCount: result.counts.sharedEdgeCount,
            g0AdjacencyCount: result.counts.g0AdjacencyCount,
            g1AdjacencyCount: result.counts.g1AdjacencyCount,
            g2AdjacencyCount: result.counts.g2AdjacencyCount,
            unresolvedG2AdjacencyCount: result.counts.unresolvedG2AdjacencyCount,
            adjacencies: adjacencies.map { adjacency in
                InspectorSurfaceAdjacency(
                    id: adjacency.edgeID,
                    edgePersistentNames: adjacency.edgePersistentNames,
                    firstFacePersistentName: adjacency.firstFacePersistentName,
                    secondFacePersistentName: adjacency.secondFacePersistentName,
                    continuity: adjacency.continuity,
                    positionGap: adjacency.positionGap,
                    normalAngle: adjacency.normalAngle,
                    curvatureGap: adjacency.curvatureGap,
                    requiresCurvatureContinuitySolve: adjacency.requiresCurvatureContinuitySolve
                )
            },
            diagnostics: result.diagnostics
        )
    }

    private func resolveContinuitySummary(for nodes: [SceneNode]) throws -> RupaCore.SurfaceContinuityResult? {
        guard nodes.count == 1, let node = nodes.first else {
            return nil
        }
        let selectedPersistentNames = generatedTopologyPersistentNames()
        guard !selectedPersistentNames.isEmpty || node.object?.geometryRole == .surface else {
            return nil
        }

        let result = try SurfaceContinuityService().summarize(
            document: document,
            objectRegistry: objectRegistry,
            currentEvaluation: currentEvaluation,
            currentGeneration: documentGeneration
        )
        guard result.counts.bSplineFaceCount > 0 else {
            return nil
        }
        return result
    }

    private func surfaceAdjacency(
        _ adjacency: RupaCore.SurfaceContinuityResult.Adjacency,
        containsAny persistentNames: Set<String>
    ) -> Bool {
        if let firstFacePersistentName = adjacency.firstFacePersistentName,
           persistentNames.contains(firstFacePersistentName) {
            return true
        }
        if let secondFacePersistentName = adjacency.secondFacePersistentName,
           persistentNames.contains(secondFacePersistentName) {
            return true
        }
        return adjacency.edgePersistentNames.contains { persistentNames.contains($0) }
    }

    private func analysisFace(
        _ face: SurfaceAnalysisResult.FaceAnalysis,
        containsAny persistentNames: Set<String>
    ) -> Bool {
        if face.facePersistentNames.contains(where: { persistentNames.contains($0) }) {
            return true
        }
        return face.edgePersistentNames.contains { persistentNames.contains($0) }
    }
}
