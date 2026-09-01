public protocol SemanticProgramCompiling: Sendable {
    /// The exact immutable registry snapshot used by this compiler.
    ///
    /// Product discovery projects this registry instead of maintaining a
    /// copied operation list. Every implementation must supply this registry;
    /// there is no empty discovery fallback.
    var semanticOperationRegistry: SemanticOperationRegistry { get }

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
