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
        let descriptorNames = descriptors.map(\.name)
        let status: CADCapabilityStatus
        if challenge.category == .sphere {
            // Sphere capability availability is owned by the same pure
            // descriptor classifier used by CADSphereCapabilityObservation.
            status = CADSphereCapabilityObservation.capabilityStatus(
                for: challenge,
                descriptorNames: descriptorNames
            )
        } else {
            let available = requiredOperationNames.isEmpty == false
                && requiredOperationNames.allSatisfy { operation in
                    descriptorNames.contains(operation)
                }
            status = CADCapabilityStatus(
                id: challenge.requiredCapability.id,
                version: challenge.requiredCapability.version,
                available: available,
                reasonCode: available ? nil : "not-exposed"
            )
        }
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
