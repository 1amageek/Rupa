import Foundation

/// Deterministic control candidate for the unavailable production sphere path.
/// It can only declare the typed capability absence and never creates an action.
struct CADSphereReferenceCandidate: CADCandidateProtocol {
    func decide(for context: CADCandidateContext) async throws -> CADCandidateDecision {
        try context.validate()
        guard context.challenge.category == .sphere,
              CADSpherePreparationCase(rawValue: context.challenge.id.rawValue) != nil else {
            throw CADBenchmarkError.invalidInput(
                caseID: context.challenge.id.rawValue,
                reason: "The sphere reference candidate received a non-preparation challenge."
            )
        }
        guard context.capabilities.status(for: context.challenge.requiredCapability)?.available == false else {
            throw CADBenchmarkError.unsupportedCapabilityMismatch(
                caseID: context.challenge.id.rawValue,
                capabilityID: context.challenge.requiredCapability.id,
                reason: "The analytic sphere capability is not unavailable in the observed context."
            )
        }
        return .unsupported(
            CADUnsupportedDeclaration(
                capabilityID: context.challenge.requiredCapability.id,
                capabilityVersion: context.challenge.requiredCapability.version,
                reason: .analyticSphereUnavailable
            )
        )
    }

    static func unsupportedDeclaration(
        for context: CADCandidateContext
    ) throws -> CADUnsupportedDeclaration {
        guard context.challenge.category == .sphere else {
            throw CADBenchmarkError.invalidInput(
                caseID: context.challenge.id.rawValue,
                reason: "Only sphere challenges may use the analytic sphere absence declaration."
            )
        }
        guard context.capabilities.status(for: context.challenge.requiredCapability)?.available == false else {
            throw CADBenchmarkError.unsupportedCapabilityMismatch(
                caseID: context.challenge.id.rawValue,
                capabilityID: context.challenge.requiredCapability.id,
                reason: "The required capability is available or was not observed as unavailable."
            )
        }
        return CADUnsupportedDeclaration(
            capabilityID: context.challenge.requiredCapability.id,
            capabilityVersion: context.challenge.requiredCapability.version,
            reason: .analyticSphereUnavailable
        )
    }
}
