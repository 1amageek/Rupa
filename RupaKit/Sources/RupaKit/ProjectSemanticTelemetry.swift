import RupaAutomation
import RupaDomainFoundation

public struct ProjectSemanticTelemetry: Sendable, Equatable {
    public let compilation: SemanticCompilationTelemetry
    public let execution: PreparedAutomationExecutionTelemetry

    public init(
        compilation: SemanticCompilationTelemetry,
        execution: PreparedAutomationExecutionTelemetry
    ) {
        self.compilation = compilation
        self.execution = execution
    }
}
