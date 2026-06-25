import RupaCore

public struct CLIConstructionPlaneSummaryResponse: Codable, Equatable, Sendable {
    public var message: String
    public var generation: UInt64
    public var dirty: Bool
    public var constructionPlaneSummary: ConstructionPlaneSummaryResult

    public init(
        constructionPlaneSummary: ConstructionPlaneSummaryResult,
        generation: DocumentGeneration,
        dirty: Bool
    ) {
        self.message = "Construction plane summary: \(constructionPlaneSummary.planes.count) saved planes."
        self.generation = generation.value
        self.dirty = dirty
        self.constructionPlaneSummary = constructionPlaneSummary
    }
}

public struct CLISketchEntitySummaryResponse: Codable, Equatable, Sendable {
    public var message: String
    public var generation: UInt64
    public var dirty: Bool
    public var sketchEntitySummary: SketchEntitySummaryResult
    public var diagnostics: [EditorDiagnostic]

    public init(
        sketchEntitySummary: SketchEntitySummaryResult,
        generation: DocumentGeneration,
        dirty: Bool
    ) {
        self.message = "Sketch entity summary: \(sketchEntitySummary.counts.sketchCount) sketches, \(sketchEntitySummary.counts.entityCount) entities, \(sketchEntitySummary.counts.regionCount) regions."
        self.generation = generation.value
        self.dirty = dirty
        self.sketchEntitySummary = sketchEntitySummary
        self.diagnostics = sketchEntitySummary.diagnostics
    }
}

public struct CLITopologySummaryResponse: Codable, Equatable, Sendable {
    public var message: String
    public var generation: UInt64
    public var dirty: Bool
    public var topologySummary: TopologySummaryResult
    public var diagnostics: [EditorDiagnostic]

    public init(
        topologySummary: TopologySummaryResult,
        generation: DocumentGeneration,
        dirty: Bool
    ) {
        self.message = "Topology summary: \(topologySummary.counts.bodyCount) bodies, \(topologySummary.counts.faceCount) faces, \(topologySummary.counts.edgeCount) edges, \(topologySummary.counts.vertexCount) vertices."
        self.generation = generation.value
        self.dirty = dirty
        self.topologySummary = topologySummary
        self.diagnostics = topologySummary.diagnostics
    }
}

public struct CLICurveAnalysisResponse: Codable, Equatable, Sendable {
    public var message: String
    public var generation: UInt64
    public var dirty: Bool
    public var curveAnalysis: CurveAnalysisResult
    public var diagnostics: [EditorDiagnostic]

    public init(
        curveAnalysis: CurveAnalysisResult,
        generation: DocumentGeneration,
        dirty: Bool
    ) {
        self.message = "Curve analysis: \(curveAnalysis.counts.curveCount) curves, \(curveAnalysis.counts.sampleCount) samples, \(curveAnalysis.counts.continuityJoinCount) continuity joins."
        self.generation = generation.value
        self.dirty = dirty
        self.curveAnalysis = curveAnalysis
        self.diagnostics = curveAnalysis.diagnostics
    }
}

public struct CLISurfaceAnalysisResponse: Codable, Equatable, Sendable {
    public var message: String
    public var generation: UInt64
    public var dirty: Bool
    public var surfaceAnalysis: SurfaceAnalysisResult
    public var diagnostics: [EditorDiagnostic]

    public init(
        surfaceAnalysis: SurfaceAnalysisResult,
        generation: DocumentGeneration,
        dirty: Bool
    ) {
        self.message = "Surface analysis: \(surfaceAnalysis.counts.bSplineFaceCount) B-spline faces, \(surfaceAnalysis.counts.sampleCount) samples, \(surfaceAnalysis.counts.trimBoundaryCount) trim boundaries."
        self.generation = generation.value
        self.dirty = dirty
        self.surfaceAnalysis = surfaceAnalysis
        self.diagnostics = surfaceAnalysis.diagnostics
    }
}

public struct CLISurfaceContinuitySummaryResponse: Codable, Equatable, Sendable {
    public var message: String
    public var generation: UInt64
    public var dirty: Bool
    public var surfaceContinuitySummary: SurfaceContinuityResult
    public var diagnostics: [EditorDiagnostic]

    public init(
        surfaceContinuitySummary: SurfaceContinuityResult,
        generation: DocumentGeneration,
        dirty: Bool
    ) {
        self.message = "Surface continuity summary: \(surfaceContinuitySummary.counts.bSplineFaceCount) B-spline faces, \(surfaceContinuitySummary.counts.sharedEdgeCount) shared edges, \(surfaceContinuitySummary.counts.g1AdjacencyCount) G1 adjacencies."
        self.generation = generation.value
        self.dirty = dirty
        self.surfaceContinuitySummary = surfaceContinuitySummary
        self.diagnostics = surfaceContinuitySummary.diagnostics
    }
}

public struct CLISurfaceFramesResponse: Codable, Equatable, Sendable {
    public var message: String
    public var generation: UInt64
    public var dirty: Bool
    public var surfaceFrames: SurfaceFrameResult
    public var diagnostics: [EditorDiagnostic]

    public init(
        surfaceFrames: SurfaceFrameResult,
        generation: DocumentGeneration,
        dirty: Bool
    ) {
        self.message = "Surface frames: \(surfaceFrames.frames.count) UVN frames."
        self.generation = generation.value
        self.dirty = dirty
        self.surfaceFrames = surfaceFrames
        self.diagnostics = surfaceFrames.diagnostics
    }
}

public struct CLISnapResolutionResponse: Codable, Equatable, Sendable {
    public var message: String
    public var generation: UInt64
    public var dirty: Bool
    public var snapResolution: SnapResolutionResult

    public init(
        snapResolution: SnapResolutionResult,
        generation: DocumentGeneration,
        dirty: Bool
    ) {
        let selectedLabel = snapResolution.selectedCandidate?.label ?? "none"
        self.message = "Snap resolution: \(snapResolution.candidates.count) candidates, selected \(selectedLabel)."
        self.generation = generation.value
        self.dirty = dirty
        self.snapResolution = snapResolution
    }
}

public struct CLISelectionMeasurementResponse: Codable, Equatable, Sendable {
    public var message: String
    public var generation: UInt64
    public var dirty: Bool
    public var selectionMeasurement: CADAgentMeasurementQueryResult

    public init(
        selectionMeasurement: CADAgentMeasurementQueryResult,
        generation: DocumentGeneration,
        dirty: Bool
    ) {
        self.message = "Selection measurement resolved."
        self.generation = generation.value
        self.dirty = dirty
        self.selectionMeasurement = selectionMeasurement
    }
}
