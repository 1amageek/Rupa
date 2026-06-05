import Foundation
import RupaAgent
import RupaCore

public struct RupaCLIResponse: Codable, Equatable, Sendable {
    public var message: String
    public var generation: UInt64
    public var dirty: Bool
    public var saved: Bool
    public var diagnostics: [RupaDiagnostic]

    public init(
        message: String,
        generation: UInt64,
        dirty: Bool,
        saved: Bool = false,
        diagnostics: [RupaDiagnostic]
    ) {
        self.message = message
        self.generation = generation
        self.dirty = dirty
        self.saved = saved
        self.diagnostics = diagnostics
    }
}

public struct RupaCLIAgentStatusResponse: Codable, Equatable, Sendable {
    public var running: Bool
    public var socketPath: String?
    public var sessionCount: Int

    public init(status: AgentStatus) {
        self.running = status.running
        self.socketPath = status.socketPath
        self.sessionCount = status.sessionCount
    }
}

public struct RupaCLISessionsResponse: Codable, Equatable, Sendable {
    public var sessions: [WorkspaceSessionSummary]

    public init(sessions: [WorkspaceSessionSummary]) {
        self.sessions = sessions
    }
}

public struct RupaCLIAttachResponse: Codable, Equatable, Sendable {
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

public struct RupaCLIParameterListResponse: Codable, Equatable, Sendable {
    public var message: String
    public var generation: UInt64
    public var dirty: Bool
    public var parameters: [RupaParameterSummary]
    public var diagnostics: [RupaDiagnostic]

    public init(result: RupaParameterListResult) {
        self.message = result.message
        self.generation = result.generation.value
        self.dirty = result.dirty
        self.parameters = result.parameters
        self.diagnostics = result.diagnostics
    }
}

public struct RupaCLIExportResponse: Codable, Equatable, Sendable {
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
    public var diagnostics: [RupaDiagnostic]

    public init(
        result: RupaExportResult,
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

public struct RupaCLIEvaluationResponse: Codable, Equatable, Sendable {
    public var message: String
    public var evaluatedGeneration: UInt64?
    public var dirty: Bool
    public var status: EvaluationStatus
    public var bodyCount: Int
    public var diagnostics: [RupaDiagnostic]

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

public struct RupaCLIMeasurementResponse: Codable, Equatable, Sendable {
    public var message: String
    public var generation: UInt64
    public var dirty: Bool
    public var measurement: RupaMeasurementResult
    public var diagnostics: [RupaDiagnostic]

    public init(
        measurement: RupaMeasurementResult,
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

public struct RupaCLIMeshSummaryResponse: Codable, Equatable, Sendable {
    public var message: String
    public var generation: UInt64
    public var dirty: Bool
    public var meshSummary: RupaMeshSummaryResult
    public var diagnostics: [RupaDiagnostic]

    public init(
        meshSummary: RupaMeshSummaryResult,
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

public struct RupaCLISaveResponse: Codable, Equatable, Sendable {
    public var message: String
    public var path: String
    public var generation: UInt64
    public var dirty: Bool
    public var saved: Bool
    public var diagnostics: [RupaDiagnostic]

    public init(result: RupaSaveResult) {
        self.message = result.message
        self.path = result.path
        self.generation = result.generation.value
        self.dirty = result.dirty
        self.saved = !result.dirty
        self.diagnostics = result.diagnostics
    }
}
