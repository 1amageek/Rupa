import Foundation
import RupaAgent
import RupaCore

public struct CLIResponse: Codable, Equatable, Sendable {
    public var message: String
    public var generation: UInt64
    public var dirty: Bool
    public var saved: Bool
    public var diagnostics: [EditorDiagnostic]

    public init(
        message: String,
        generation: UInt64,
        dirty: Bool,
        saved: Bool = false,
        diagnostics: [EditorDiagnostic]
    ) {
        self.message = message
        self.generation = generation
        self.dirty = dirty
        self.saved = saved
        self.diagnostics = diagnostics
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
