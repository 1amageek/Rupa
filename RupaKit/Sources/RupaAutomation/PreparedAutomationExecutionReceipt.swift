import RupaCore

/// Complete immutable result of a prepared source execution.
public struct PreparedAutomationExecutionReceipt: Sendable, Equatable {
    public let stepReceipts: [PreparedAutomationStepReceipt]
    public let outputBindings: [PreparedAutomationOutputBinding]
    public let diagnostics: [EditorDiagnostic]
    public let telemetry: PreparedAutomationExecutionTelemetry

    init(
        stepReceipts: [PreparedAutomationStepReceipt],
        outputBindings: [PreparedAutomationOutputBinding],
        diagnostics: [EditorDiagnostic],
        telemetry: PreparedAutomationExecutionTelemetry
    ) {
        self.stepReceipts = stepReceipts
        self.outputBindings = outputBindings
        self.diagnostics = diagnostics
        self.telemetry = telemetry
    }
}
