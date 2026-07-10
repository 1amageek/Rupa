import SwiftCAD
import RupaCoreTypes

public struct TopologySummaryService: Sendable {
    private let snapshotService: TopologySnapshotService

    public init(pipeline: CADPipeline? = nil) {
        snapshotService = TopologySnapshotService(pipeline: pipeline)
    }

    public func summarize(
        document: DesignDocument,
        displayUnit: LengthDisplayUnit,
        objectRegistry: ObjectTypeRegistry = .builtIn,
        currentEvaluation: DocumentEvaluationContext? = nil,
        currentGeneration: DocumentGeneration? = nil
    ) throws -> TopologySummaryResult {
        let snapshot = try snapshotService.snapshot(
            document: document,
            objectRegistry: objectRegistry,
            currentEvaluation: currentEvaluation,
            currentGeneration: currentGeneration
        )
        let message = snapshot.hasGeneratedTopology
            ? "Topology summary completed with \(snapshot.entries.count) generated persistent references."
            : "Document source is valid. No generated topology."
        return TopologySummaryResult(
            displayUnit: displayUnit,
            counts: snapshot.counts,
            entries: snapshot.entries,
            diagnostics: [
                EditorDiagnostic(
                    severity: .info,
                    message: message
                ),
            ]
        )
    }
}
