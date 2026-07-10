import SwiftCAD
import RupaCoreTypes

public struct SketchDimensionSummaryService: Sendable {
    private let snapshotService: SketchDimensionSnapshotService

    public init() {
        snapshotService = SketchDimensionSnapshotService()
    }

    public func summarize(
        document: DesignDocument,
        targets: [SelectionTarget],
        displayUnit: LengthDisplayUnit,
        objectRegistry: ObjectTypeRegistry = .builtIn
    ) throws -> SketchDimensionSummaryResult {
        let snapshot = try snapshotService.snapshot(
            document: document,
            targets: targets,
            objectRegistry: objectRegistry
        )
        return SketchDimensionSummaryResult(
            displayUnit: displayUnit,
            counts: snapshot.counts,
            entries: snapshot.entries,
            diagnostics: [
                EditorDiagnostic(
                    severity: .info,
                    message: "Sketch dimension summary completed with \(snapshot.entries.count) editable dimension candidate(s)."
                ),
            ]
        )
    }
}
