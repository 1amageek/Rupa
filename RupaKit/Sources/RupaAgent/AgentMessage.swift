import Foundation
import RupaAutomation
import RupaCore
import SwiftCAD

public enum AgentRequest: Codable, Equatable, Sendable {
    case status
    case sessions
    case execute(
        sessionID: UUID,
        command: AutomationCommand,
        expectedGeneration: DocumentGeneration?
    )
    case parameters(
        sessionID: UUID,
        expectedGeneration: DocumentGeneration?
    )
    case setParameterExpression(
        sessionID: UUID,
        name: String,
        expression: String,
        kind: QuantityKind,
        defaults: RupaParameterExpressionDefaults,
        expectedGeneration: DocumentGeneration?
    )
    case evaluate(
        sessionID: UUID,
        expectedGeneration: DocumentGeneration?
    )
    case measure(
        sessionID: UUID,
        expectedGeneration: DocumentGeneration?
    )
    case meshSummary(
        sessionID: UUID,
        expectedGeneration: DocumentGeneration?
    )
    case save(
        sessionID: UUID,
        expectedGeneration: DocumentGeneration?
    )
    case export(
        sessionID: UUID,
        outputPath: String,
        expectedGeneration: DocumentGeneration?,
        options: RupaExportOptions,
        dryRun: Bool
    )
}

public enum AgentResponse: Codable, Equatable, Sendable {
    case status(AgentStatus)
    case sessions([WorkspaceSessionSummary])
    case command(AutomationResult)
    case parameters(RupaParameterListResult)
    case evaluation(EvaluationSnapshot)
    case measurement(RupaMeasurementResult)
    case meshSummary(RupaMeshSummaryResult)
    case save(RupaSaveResult)
    case export(RupaExportResult)
    case failure(RupaError)
}

public struct AgentStatus: Codable, Equatable, Sendable {
    public var running: Bool
    public var socketPath: String?
    public var sessionCount: Int

    public init(
        running: Bool,
        socketPath: String?,
        sessionCount: Int
    ) {
        self.running = running
        self.socketPath = socketPath
        self.sessionCount = sessionCount
    }
}
