import RupaAgentProtocol
import RupaAutomation
import SwiftCAD

/// Adapts a public candidate action to one production automation command.
/// The category facade supplies the mapping closure; lifecycle code only invokes it.
@MainActor
struct CADCaseActionRouting {
    let operationName: String
    private let commandBuilder: @MainActor (
        CADCandidateAction,
        CADChallenge,
        ModelingTolerance
    ) throws -> AutomationCommand

    init(
        operationName: String,
        commandBuilder: @escaping @MainActor (
            CADCandidateAction,
            CADChallenge,
            ModelingTolerance
        ) throws -> AutomationCommand
    ) {
        self.operationName = operationName
        self.commandBuilder = commandBuilder
    }

    func makeCommand(
        from action: CADCandidateAction,
        challenge: CADChallenge,
        modelingTolerance: ModelingTolerance
    ) throws -> AutomationCommand {
        try commandBuilder(action, challenge, modelingTolerance)
    }
}
