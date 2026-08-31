public protocol SemanticProgramCompiling: Sendable {
    func compile(
        _ request: SemanticDirectRequest,
        context: SemanticCompilationContext,
        limits: SemanticProgramLimitPolicy,
        cancellation: any SemanticCompilationCancellation
    ) throws -> SemanticCompilationResult

    func compile(
        _ program: SemanticProgram,
        context: SemanticCompilationContext,
        limits: SemanticProgramLimitPolicy,
        cancellation: any SemanticCompilationCancellation
    ) throws -> SemanticCompilationResult
}

public extension SemanticProgramCompiling {
    func compile(
        _ request: SemanticDirectRequest,
        context: SemanticCompilationContext,
        limits: SemanticProgramLimitPolicy
    ) throws -> SemanticCompilationResult {
        try compile(
            request,
            context: context,
            limits: limits,
            cancellation: NeverSemanticCompilationCancellation()
        )
    }

    func compile(
        _ program: SemanticProgram,
        context: SemanticCompilationContext,
        limits: SemanticProgramLimitPolicy
    ) throws -> SemanticCompilationResult {
        try compile(
            program,
            context: context,
            limits: limits,
            cancellation: NeverSemanticCompilationCancellation()
        )
    }
}

public typealias SemanticProgramCompiler = SemanticProgramCompiling
