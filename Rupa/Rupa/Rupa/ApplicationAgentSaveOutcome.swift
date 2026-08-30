import RupaAgentProtocol
import RupaCoreTypes

enum ApplicationAgentSaveOutcome: Equatable, Sendable {
    case saved(SaveResult)
    case committed(AgentCommittedMutationOutcome)
}
