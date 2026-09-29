import RupaCore

/// The whole-document analyses the workspace view shows, kept for the inputs they were made from.
///
/// SwiftUI evaluates the view's body, and every property it reads, on each state change, hover
/// included. The surface analysis, surface continuity, surface source summary and section analysis
/// depend on the document generation and their own options, not on the selection, which only
/// decides whether they show and which of their rows. Each is made once per input here instead of
/// up to three times per render. The cache belongs to one document lifetime (the view is rebuilt
/// for a new document), so a generation names one document state.
final class WorkspaceDocumentAnalysisCache {
    struct SurfaceAnalysisKey: Equatable {
        var generation: DocumentGeneration
        var displayUnit: LengthDisplayUnit
        var options: SurfaceAnalysisOptions
    }

    struct SurfaceContinuityKey: Equatable {
        var generation: DocumentGeneration
        var displayUnit: LengthDisplayUnit
    }

    struct SurfaceSourceSummaryKey: Equatable {
        var generation: DocumentGeneration
        var displayUnit: LengthDisplayUnit
        var controlPointDisplays: [SurfaceControlPointDisplayID: SurfaceControlPointDisplay]
        var frameDisplays: [SurfaceFrameDisplayID: SurfaceFrameDisplay]
    }

    struct SectionAnalysisKey: Equatable {
        var generation: DocumentGeneration
        var displayUnit: LengthDisplayUnit
        var query: SectionAnalysisQuery
    }

    let surfaceAnalysis = MemoizedResults<SurfaceAnalysisKey, SurfaceAnalysisResult>()
    let surfaceContinuity = MemoizedResults<SurfaceContinuityKey, RupaCore.SurfaceContinuityResult>()
    let surfaceSourceSummary = MemoizedResults<SurfaceSourceSummaryKey, SurfaceSourceSummaryResult>()
    /// The command's section and the selected construction plane's section can show together.
    let sectionAnalysis = MemoizedResults<SectionAnalysisKey, SectionAnalysisResult>(capacity: 2)
}

/// The results made for the most recent distinct keys, failures included, so a failing input is
/// not retried on every read either.
final class MemoizedResults<Key: Equatable, Value> {
    private let capacity: Int
    private var entries: [(key: Key, result: Result<Value, any Error>)] = []

    init(capacity: Int = 1) {
        precondition(capacity > 0, "A memo holds at least one result.")
        self.capacity = capacity
    }

    func value(for key: Key, make: () throws -> Value) throws -> Value {
        if let index = entries.firstIndex(where: { $0.key == key }) {
            let entry = entries.remove(at: index)
            entries.append(entry)
            return try entry.result.get()
        }
        let result = Result { try make() }
        entries.append((key, result))
        if entries.count > capacity {
            entries.removeFirst(entries.count - capacity)
        }
        return try result.get()
    }
}
