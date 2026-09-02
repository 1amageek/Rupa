import RupaAgentProtocol
import RupaDomainFoundation

/// One immutable semantic program and the output metadata needed to project
/// its committed receipt into category evidence.
struct CADSemanticProgramPlan: Sendable, Equatable {
    struct Step: Sendable, Equatable {
        let symbol: String
        let operationID: DomainCapabilityID
        let outputs: [AgentSemanticOutputReference]
    }

    let request: AgentSemanticProgramRequest
    let steps: [Step]

    var commandCount: Int { steps.count }
}
