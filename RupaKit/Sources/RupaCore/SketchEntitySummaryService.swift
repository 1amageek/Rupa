import SwiftCAD
import RupaCoreTypes

public struct SketchEntitySummaryService: Sendable {
    private let snapshotService: SketchEntitySnapshotService

    public init() {
        snapshotService = SketchEntitySnapshotService()
    }

    public func summarize(
        document: DesignDocument,
        displayUnit: LengthDisplayUnit,
        objectRegistry: ObjectTypeRegistry = .builtIn
    ) throws -> SketchEntitySummaryResult {
        let snapshot = try snapshotService.snapshot(
            document: document,
            objectRegistry: objectRegistry
        )
        return SketchEntitySummaryResult(
            displayUnit: displayUnit,
            counts: snapshot.counts,
            sketches: snapshot.sketches,
            entries: snapshot.entries,
            regions: snapshot.regions,
            diagnostics: snapshot.diagnostics + [
                EditorDiagnostic(
                    severity: .info,
                    message: "Sketch entity summary completed with \(snapshot.entries.count) source entity references and \(snapshot.regions.count) region references."
                ),
            ]
        )
    }
}
