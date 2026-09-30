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

    let surfaceAnalysis = MemoizedResults<SurfaceAnalysisKey, SurfaceAnalysisResult, any Error>()
    let surfaceContinuity = MemoizedResults<SurfaceContinuityKey, RupaCore.SurfaceContinuityResult, any Error>()
    let surfaceSourceSummary = MemoizedResults<SurfaceSourceSummaryKey, SurfaceSourceSummaryResult, any Error>()
    /// The command's section and the selected construction plane's section can show together.
    let sectionAnalysis = MemoizedResults<SectionAnalysisKey, SectionAnalysisResult, any Error>(capacity: 2)
    /// Every shared definition's selection, read by each sidebar row and the inspector.
    let sharedDefinitions = MemoizedResults<
        DocumentGeneration, [ComponentDefinitionID: Result<SharedDefinitionSelection, any Error>], any Error
    >()
}
