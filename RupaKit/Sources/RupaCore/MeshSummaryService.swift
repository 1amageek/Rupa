import SwiftCAD
import RupaCoreTypes

public struct MeshSummaryService: Sendable {
    private let snapshotService: MeshSnapshotService

    public init(pipeline: CADPipeline? = nil) {
        snapshotService = MeshSnapshotService(pipeline: pipeline)
    }

    public func summarize(
        document: DesignDocument,
        ruler: RulerConfiguration,
        objectRegistry: ObjectTypeRegistry = .builtIn,
        currentEvaluation: DocumentEvaluationContext? = nil,
        currentGeneration: DocumentGeneration? = nil
    ) throws -> MeshSummaryResult {
        let snapshot = try snapshotService.snapshot(
            document: document,
            objectRegistry: objectRegistry,
            currentEvaluation: currentEvaluation,
            currentGeneration: currentGeneration
        )
        let diagnostics: [EditorDiagnostic]
        if snapshot.bodyCount == 0 {
            diagnostics = [
                EditorDiagnostic(
                    severity: .info,
                    message: "Document source is valid. No generated body meshes."
                ),
            ]
        } else {
            diagnostics = [
                EditorDiagnostic(
                    severity: .info,
                    message: "Mesh summary completed with \(snapshot.bodyCount) generated body meshes."
                ),
            ] + WorkspacePrecisionDiagnosticService().diagnostics(
                for: snapshot.bounds,
                ruler: ruler,
                displayUnit: ruler.displayUnit
            )
        }
        return MeshSummaryResult(
            displayUnit: ruler.displayUnit,
            bodyCount: snapshot.bodyCount,
            vertexCount: snapshot.vertexCount,
            normalCount: snapshot.normalCount,
            triangleCount: snapshot.triangleCount,
            indexedElementCount: snapshot.indexedElementCount,
            bounds: snapshot.bounds,
            bodies: snapshot.bodies,
            diagnostics: diagnostics
        )
    }
}
