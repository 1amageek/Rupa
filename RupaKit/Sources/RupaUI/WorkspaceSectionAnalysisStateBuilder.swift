import RupaCore

struct WorkspaceSectionAnalysisStateBuilder {
    var document: DesignDocument
    var currentEvaluation: DocumentEvaluationContext?
    var documentGeneration: DocumentGeneration
    var displayUnit: LengthDisplayUnit
    var objectRegistry: ObjectTypeRegistry

    func analysisSummary(for nodes: [SceneNode]) -> SectionAnalysisResult? {
        switch analysisSummaryResult(for: nodes) {
        case .success(let summary):
            return summary
        case .failure:
            return nil
        }
    }

    func analysisSummaryResult(for nodes: [SceneNode]) -> Result<SectionAnalysisResult?, Error> {
        do {
            return .success(try resolveAnalysisSummary(for: nodes))
        } catch {
            return .failure(error)
        }
    }

    private func resolveAnalysisSummary(for nodes: [SceneNode]) throws -> SectionAnalysisResult? {
        guard let query = sectionAnalysisQuery(for: nodes) else {
            return nil
        }
        return try SectionAnalysisService().analyze(
            document: document,
            query: query,
            activeConstructionPlaneID: nil,
            displayUnit: displayUnit,
            objectRegistry: objectRegistry,
            currentEvaluation: currentEvaluation,
            currentGeneration: documentGeneration
        )
    }

    private func sectionAnalysisQuery(for nodes: [SceneNode]) -> SectionAnalysisQuery? {
        guard nodes.count == 1,
              let node = nodes.first,
              let source = sectionAnalysisSource(for: node) else {
            return nil
        }
        return SectionAnalysisQuery(
            source: source,
            toleranceMeters: nil,
            includesIntersectionSegments: true,
            maximumIntersectionSegments: 2_048
        )
    }

    private func sectionAnalysisSource(for node: SceneNode) -> SectionAnalysisQuery.Source? {
        if let constructionPlaneID = node.reference?.constructionPlaneID {
            return .constructionPlane(constructionPlaneID)
        }
        if node.reference?.kind == .construction || node.object?.category == .construction {
            return .sceneNode(node.id)
        }
        return nil
    }
}
