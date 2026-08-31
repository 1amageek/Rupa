import RupaAutomation

/// One complete prepared source program and the authority required to stage it.
public struct ProjectPreparedProgramMutation: Sendable {
    public let program: PreparedAutomationProgram
    public let authority: ProjectAuthorityCoordinate
    public let resultLimit: ProjectPreparedProgramResultLimit

    public init(
        program: PreparedAutomationProgram,
        authority: ProjectAuthorityCoordinate,
        resultLimit: ProjectPreparedProgramResultLimit
    ) {
        self.program = program
        self.authority = authority
        self.resultLimit = resultLimit
    }
}
