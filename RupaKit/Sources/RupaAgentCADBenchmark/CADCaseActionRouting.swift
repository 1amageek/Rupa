import RupaAgentProtocol
import RupaAutomation
import SwiftCAD

/// Adapts a public candidate action to one bounded production action plan.
/// The category facade supplies the mapping closure; lifecycle code only invokes it.
@MainActor
struct CADCaseActionRouting {
    let operationName: String
    private let planBuilder: @MainActor (
        CADCandidateAction,
        CADChallenge,
        ModelingTolerance
    ) throws -> CADCaseActionPlan

    init(
        operationName: String,
        commandBuilder: @escaping @MainActor (
            CADCandidateAction,
            CADChallenge,
            ModelingTolerance
        ) throws -> AutomationCommand
    ) {
        self.operationName = operationName
        self.planBuilder = { action, challenge, tolerance in
            .command(try commandBuilder(action, challenge, tolerance))
        }
    }

    init(
        operationName: String,
        planBuilder: @escaping @MainActor (
            CADCandidateAction,
            CADChallenge,
            ModelingTolerance
        ) throws -> CADCaseActionPlan
    ) {
        self.operationName = operationName
        self.planBuilder = planBuilder
    }

    func makePlan(
        from action: CADCandidateAction,
        challenge: CADChallenge,
        modelingTolerance: ModelingTolerance
    ) throws -> CADCaseActionPlan {
        try planBuilder(action, challenge, modelingTolerance)
    }
}
