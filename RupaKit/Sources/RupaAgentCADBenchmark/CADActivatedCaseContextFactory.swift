import RupaAgentRuntime

/// Builds the candidate-visible context shared by request and live execution.
@MainActor
struct CADActivatedCaseContextFactory {
    static func make(
        challenge: CADChallenge,
        controller: ProjectAgentCommandController
    ) -> CADCandidateContext {
        let descriptors = controller.capabilityDescriptors()
        let hasSemanticProgramRoute = descriptors.contains {
            $0.access == .agentRequest && $0.semanticOperation != nil
        }
        let status = CADCapabilityStatus(
            id: challenge.requiredCapability.id,
            version: challenge.requiredCapability.version,
            available: hasSemanticProgramRoute,
            reasonCode: hasSemanticProgramRoute ? nil : "semantic-program-unavailable"
        )
        return CADCandidateContext(
            challenge: challenge,
            capabilities: CADCapabilitySnapshot(
                version: "agent-capabilities.v1",
                statuses: [status]
            ),
            remainingRounds: challenge.budget.maximumRounds,
            remainingActions: challenge.budget.maximumActions
        )
    }
}
