import RupaDomainFoundation
import RupaProject

/// A compiled semantic source program bound to one exact project authority.
public struct ProjectSemanticProgramRequest: Sendable {
    public let compilation: SemanticCompilationResult
    public let authority: ProjectAuthorityCoordinate
    public let dryRun: Bool
    public let resultBudget: ProjectSemanticResultBudget

    public init(
        compilation: SemanticCompilationResult,
        authority: ProjectAuthorityCoordinate,
        dryRun: Bool,
        resultBudget: ProjectSemanticResultBudget
    ) {
        self.compilation = compilation
        self.authority = authority
        self.dryRun = dryRun
        self.resultBudget = resultBudget
    }
}
