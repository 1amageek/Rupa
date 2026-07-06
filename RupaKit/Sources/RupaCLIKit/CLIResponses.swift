import Foundation
import RupaAgentProtocol
import RupaCore

public struct CLIResponse: Codable, Equatable, Sendable {
    public var message: String
    public var generation: UInt64
    public var dirty: Bool
    public var saved: Bool
    public var primaryFeatureID: FeatureID?
    public var createdFeatureIDs: [FeatureID]?
    public var diagnostics: [EditorDiagnostic]
    public var workspaceScale: WorkspaceScaleSnapshot?
    public var workspaceInteractionScale: WorkspaceInteractionScaleSnapshot?
    public var workspaceBounds: MeasurementResult.Bounds?
    public var workspacePrecision: WorkspacePrecisionReport?
    public var workspaceScaleRecommendation: WorkspaceScaleRecommendation?
    public var workspaceScalePresetOptions: [WorkspaceScalePresetProfile]?
    public var viewportGridSettings: ViewportGridSettings?
    public var viewportGridScale: ViewportGridScaleSnapshot?
    public var savedViews: [SavedView]?
    public var savedViewID: SavedViewID?
    public var drawingProjection: DrawingProjectionResult?
    public var drawingProjectionSVGPath: String?
    public var drawingProjectionSVGByteCount: UInt64?
    public var drawingProjectionPDFPath: String?
    public var drawingProjectionPDFByteCount: UInt64?

    public init(
        message: String,
        generation: UInt64,
        dirty: Bool,
        saved: Bool = false,
        primaryFeatureID: FeatureID? = nil,
        createdFeatureIDs: [FeatureID]? = nil,
        diagnostics: [EditorDiagnostic],
        workspaceScale: WorkspaceScaleSnapshot? = nil,
        workspaceInteractionScale: WorkspaceInteractionScaleSnapshot? = nil,
        workspaceBounds: MeasurementResult.Bounds? = nil,
        workspacePrecision: WorkspacePrecisionReport? = nil,
        workspaceScaleRecommendation: WorkspaceScaleRecommendation? = nil,
        workspaceScalePresetOptions: [WorkspaceScalePresetProfile]? = nil,
        viewportGridSettings: ViewportGridSettings? = nil,
        viewportGridScale: ViewportGridScaleSnapshot? = nil,
        savedViews: [SavedView]? = nil,
        savedViewID: SavedViewID? = nil,
        drawingProjection: DrawingProjectionResult? = nil,
        drawingProjectionSVGPath: String? = nil,
        drawingProjectionSVGByteCount: UInt64? = nil,
        drawingProjectionPDFPath: String? = nil,
        drawingProjectionPDFByteCount: UInt64? = nil
    ) {
        self.message = message
        self.generation = generation
        self.dirty = dirty
        self.saved = saved
        self.primaryFeatureID = primaryFeatureID
        self.createdFeatureIDs = createdFeatureIDs
        self.diagnostics = diagnostics
        self.workspaceScale = workspaceScale
        self.workspaceInteractionScale = workspaceInteractionScale
        self.workspaceBounds = workspaceBounds
        self.workspacePrecision = workspacePrecision
        self.workspaceScaleRecommendation = workspaceScaleRecommendation
        self.workspaceScalePresetOptions = workspaceScalePresetOptions
        self.viewportGridSettings = viewportGridSettings
        self.viewportGridScale = viewportGridScale
        self.savedViews = savedViews
        self.savedViewID = savedViewID
        self.drawingProjection = drawingProjection
        self.drawingProjectionSVGPath = drawingProjectionSVGPath
        self.drawingProjectionSVGByteCount = drawingProjectionSVGByteCount
        self.drawingProjectionPDFPath = drawingProjectionPDFPath
        self.drawingProjectionPDFByteCount = drawingProjectionPDFByteCount
    }
}

public struct CLIAgentStatusResponse: Codable, Equatable, Sendable {
    public var running: Bool
    public var socketPath: String?
    public var sessionCount: Int

    public init(status: AgentStatus) {
        self.running = status.running
        self.socketPath = status.socketPath
        self.sessionCount = status.sessionCount
    }
}

public struct CLISessionsResponse: Codable, Equatable, Sendable {
    public var sessions: [WorkspaceSessionSummary]

    public init(sessions: [WorkspaceSessionSummary]) {
        self.sessions = sessions
    }
}

public struct CLIAttachResponse: Codable, Equatable, Sendable {
    public var message: String
    public var sessionID: UUID
    public var path: String?
    public var displayName: String
    public var dirty: Bool
    public var generation: UInt64

    public init(session: WorkspaceSessionSummary) {
        self.message = "Attached to Rupa session \(session.id.uuidString)."
        self.sessionID = session.id
        self.path = session.path
        self.displayName = session.displayName
        self.dirty = session.dirty
        self.generation = session.generation.value
    }
}

public struct CLIParameterListResponse: Codable, Equatable, Sendable {
    public var message: String
    public var generation: UInt64
    public var dirty: Bool
    public var parameters: [ParameterSummary]
    public var diagnostics: [EditorDiagnostic]

    public init(result: ParameterListResult) {
        self.message = result.message
        self.generation = result.generation.value
        self.dirty = result.dirty
        self.parameters = result.parameters
        self.diagnostics = result.diagnostics
    }
}

public struct CLIExportResponse: Codable, Equatable, Sendable {
    public var message: String
    public var generation: UInt64
    public var dirty: Bool
    public var outputPath: String
    public var format: String
    public var byteCount: UInt64
    public var dryRun: Bool
    public var presetName: String?
    public var outputUnit: String
    public var destinationPolicy: String
    public var diagnostics: [EditorDiagnostic]

    public init(
        result: ExportResult,
        dirty: Bool
    ) {
        self.message = result.message
        self.generation = result.generation.value
        self.dirty = dirty
        self.outputPath = result.outputPath
        self.format = result.format.rawValue
        self.byteCount = result.byteCount
        self.dryRun = result.dryRun
        self.presetName = result.presetName
        self.outputUnit = result.outputUnit.rawValue
        self.destinationPolicy = result.destinationPolicy.rawValue
        self.diagnostics = result.diagnostics
    }
}

public struct CLIEvaluationResponse: Codable, Equatable, Sendable {
    public var message: String
    public var evaluatedGeneration: UInt64?
    public var dirty: Bool
    public var status: EvaluationStatus
    public var bodyCount: Int
    public var diagnostics: [EditorDiagnostic]

    public init(
        snapshot: EvaluationSnapshot,
        dirty: Bool
    ) {
        self.message = Self.message(for: snapshot)
        self.evaluatedGeneration = snapshot.evaluatedGeneration?.value
        self.dirty = dirty
        self.status = snapshot.status
        self.bodyCount = snapshot.bodyCount
        self.diagnostics = snapshot.diagnostics
    }

    private static func message(for snapshot: EvaluationSnapshot) -> String {
        switch snapshot.status {
        case .notEvaluated:
            "Document has not been evaluated."
        case .valid:
            "Evaluation completed with \(snapshot.bodyCount) generated bodies."
        case .failed(let message):
            "Evaluation failed: \(message)"
        }
    }
}

public struct CLIMeasurementResponse: Codable, Equatable, Sendable {
    public var message: String
    public var generation: UInt64
    public var dirty: Bool
    public var measurement: MeasurementResult
    public var diagnostics: [EditorDiagnostic]

    public init(
        measurement: MeasurementResult,
        generation: DocumentGeneration,
        dirty: Bool
    ) {
        self.message = measurement.message
        self.generation = generation.value
        self.dirty = dirty
        self.measurement = measurement
        self.diagnostics = measurement.diagnostics
    }
}

public struct CLIMeshSummaryResponse: Codable, Equatable, Sendable {
    public var message: String
    public var generation: UInt64
    public var dirty: Bool
    public var meshSummary: MeshSummaryResult
    public var diagnostics: [EditorDiagnostic]

    public init(
        meshSummary: MeshSummaryResult,
        generation: DocumentGeneration,
        dirty: Bool
    ) {
        self.message = meshSummary.message
        self.generation = generation.value
        self.dirty = dirty
        self.meshSummary = meshSummary
        self.diagnostics = meshSummary.diagnostics
    }
}

public struct CLISurfaceSourceSummaryResponse: Codable, Equatable, Sendable {
    public var message: String
    public var generation: UInt64
    public var dirty: Bool
    public var surfaceSourceSummary: SurfaceSourceSummaryResult
    public var diagnostics: [EditorDiagnostic]

    public init(
        surfaceSourceSummary: SurfaceSourceSummaryResult,
        generation: DocumentGeneration,
        dirty: Bool
    ) {
        self.message = "Surface source summary: \(surfaceSourceSummary.counts.sourceCount) sources, \(surfaceSourceSummary.counts.patchCount) patches, \(surfaceSourceSummary.counts.controlVertexCount) source control vertices, \(surfaceSourceSummary.counts.controlPointCount) B-spline control points."
        self.generation = generation.value
        self.dirty = dirty
        self.surfaceSourceSummary = surfaceSourceSummary
        self.diagnostics = surfaceSourceSummary.diagnostics
    }
}

public struct CLISketchDimensionSummaryResponse: Codable, Equatable, Sendable {
    public var message: String
    public var generation: UInt64
    public var dirty: Bool
    public var sketchDimensionSummary: SketchDimensionSummaryResult
    public var diagnostics: [EditorDiagnostic]

    public init(
        sketchDimensionSummary: SketchDimensionSummaryResult,
        generation: DocumentGeneration,
        dirty: Bool
    ) {
        self.message = "Sketch dimension summary: \(sketchDimensionSummary.counts.targetCount) targets, \(sketchDimensionSummary.counts.entryCount) candidates."
        self.generation = generation.value
        self.dirty = dirty
        self.sketchDimensionSummary = sketchDimensionSummary
        self.diagnostics = sketchDimensionSummary.diagnostics
    }
}

public struct CLIObjectDimensionSummaryResponse: Codable, Equatable, Sendable {
    public var message: String
    public var generation: UInt64
    public var dirty: Bool
    public var objectDimensionSummary: ObjectDimensionSummaryResult
    public var diagnostics: [EditorDiagnostic]

    public init(
        objectDimensionSummary: ObjectDimensionSummaryResult,
        generation: DocumentGeneration,
        dirty: Bool
    ) {
        self.message = "Object dimension summary: \(objectDimensionSummary.counts.targetCount) targets, \(objectDimensionSummary.counts.entryCount) candidates."
        self.generation = generation.value
        self.dirty = dirty
        self.objectDimensionSummary = objectDimensionSummary
        self.diagnostics = objectDimensionSummary.diagnostics
    }
}

public struct CLISaveResponse: Codable, Equatable, Sendable {
    public var message: String
    public var path: String
    public var generation: UInt64
    public var dirty: Bool
    public var saved: Bool
    public var diagnostics: [EditorDiagnostic]

    public init(result: SaveResult) {
        self.message = result.message
        self.path = result.path
        self.generation = result.generation.value
        self.dirty = result.dirty
        self.saved = !result.dirty
        self.diagnostics = result.diagnostics
    }
}

public struct CLISelectionResponse: Codable, Equatable, Sendable {
    public var message: String
    public var generation: UInt64
    public var dirty: Bool
    public var selectedTargetCount: Int
    public var selectedReferenceCount: Int
    public var selectedTargets: [SelectionTarget]
    public var selectedReferences: [SelectionReference]
    public var hoveredTarget: SelectionTarget?
    public var hoveredReference: SelectionReference?
    public var diagnostics: [EditorDiagnostic]

    public init(result: SelectionStateResult) {
        self.message = result.message
        self.generation = result.generation.value
        self.dirty = result.dirty
        self.selectedTargetCount = result.selectedTargets.count
        self.selectedReferenceCount = result.selectedReferences.count
        self.selectedTargets = result.selectedTargets
        self.selectedReferences = result.selectedReferences
        self.hoveredTarget = result.hoveredTarget
        self.hoveredReference = result.hoveredReference
        self.diagnostics = result.diagnostics
    }
}
