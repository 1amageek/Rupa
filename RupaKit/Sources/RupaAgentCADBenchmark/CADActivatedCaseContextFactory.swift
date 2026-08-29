import RupaAgentRuntime

/// Builds the candidate-visible context shared by request and live execution.
@MainActor
struct CADActivatedCaseContextFactory {
    static func make(
        challenge: CADChallenge,
        operationName: String,
        controller: ProjectAgentCommandController
    ) -> CADCandidateContext {
        let requiredOperationNames: [String]
        if challenge.category == .compound {
            requiredOperationNames = CADCompoundGeometryMapping.requiredOperationNames(
                for: challenge
            )
        } else {
            requiredOperationNames = operationName.isEmpty ? [] : [operationName]
        }
        let descriptors = controller.capabilityDescriptors()
        let available = requiredOperationNames.isEmpty == false
            && requiredOperationNames.allSatisfy { operation in
                descriptors.contains { $0.name == operation }
            }
        return CADCandidateContext(
            challenge: challenge,
            capabilities: CADCapabilitySnapshot(
                version: "agent-capabilities.v1",
                statuses: [
                    CADCapabilityStatus(
                        id: challenge.requiredCapability.id,
                        version: challenge.requiredCapability.version,
                        available: available,
                        reasonCode: available ? nil : "not-exposed"
                    ),
                ]
            ),
            remainingRounds: challenge.budget.maximumRounds,
            remainingActions: challenge.budget.maximumActions
        )
    }
}
