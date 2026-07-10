import SwiftCAD
import RupaCoreTypes

public struct ObjectDimensionSummaryService: Sendable {
    private let snapshotService: ObjectDimensionSnapshotService

    public init() {
        snapshotService = ObjectDimensionSnapshotService()
    }

    public func summarize(
        document: DesignDocument,
        targets: [SelectionTarget],
        displayUnit: LengthDisplayUnit,
        objectRegistry: ObjectTypeRegistry = .builtIn
    ) throws -> ObjectDimensionSummaryResult {
        let snapshot = try snapshotService.snapshot(
            document: document,
            targets: targets,
            objectRegistry: objectRegistry
        )
        return ObjectDimensionSummaryResult(
            displayUnit: displayUnit,
            counts: snapshot.counts,
            entries: snapshot.entries,
            diagnostics: [
                EditorDiagnostic(
                    severity: .info,
                    message: "Object dimension summary completed with \(snapshot.entries.count) editable dimension candidate(s)."
                ),
            ]
        )
    }
}
