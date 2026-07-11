import RupaCore

public struct AutomationBatchMetrics: Codable, Equatable, Sendable {
    public var commandCount: Int
    public var evaluationPassCount: UInt64
    public var historyEntryCount: Int
    public var richResultCount: Int
    public var modelingEvaluation: ModelingEvaluationMetrics?

    public init(
        commandCount: Int,
        evaluationPassCount: UInt64,
        historyEntryCount: Int,
        richResultCount: Int,
        modelingEvaluation: ModelingEvaluationMetrics? = nil
    ) {
        self.commandCount = commandCount
        self.evaluationPassCount = evaluationPassCount
        self.historyEntryCount = historyEntryCount
        self.richResultCount = richResultCount
        self.modelingEvaluation = modelingEvaluation
    }

    public static let empty = AutomationBatchMetrics(
        commandCount: 0,
        evaluationPassCount: 0,
        historyEntryCount: 0,
        richResultCount: 0,
        modelingEvaluation: nil
    )
}
