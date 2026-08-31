import RupaAutomation

public struct SemanticCompilationResult: Sendable {
    public let preparedProgram: PreparedAutomationProgram
    public let orderedNodeSymbols: [ProgramNodeSymbol]
    public let requestedOutputs: [CompiledSemanticOutputRequest]
    public let telemetry: SemanticCompilationTelemetry
    public let resultCharge: SemanticResultCharge

    init(
        preparedProgram: PreparedAutomationProgram,
        orderedNodeSymbols: [ProgramNodeSymbol],
        requestedOutputs: [CompiledSemanticOutputRequest],
        telemetry: SemanticCompilationTelemetry,
        resultCharge: SemanticResultCharge
    ) {
        self.preparedProgram = preparedProgram
        self.orderedNodeSymbols = orderedNodeSymbols
        self.requestedOutputs = requestedOutputs
        self.telemetry = telemetry
        self.resultCharge = resultCharge
    }
}

public typealias CompiledSemanticProgram = SemanticCompilationResult
