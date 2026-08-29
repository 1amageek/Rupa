import Foundation
import RupaAgentProtocol
import RupaAgentRuntime

/// Typed observation of the production Agent capability surface for spheres.
enum CADSphereCapabilityObservationError: Error, Equatable, Sendable, CustomStringConvertible {
    case analyticSphereUnavailable(
        capabilityID: String,
        capabilityVersion: String,
        snapshotVersion: String
    )
    case unexpectedControllerResponse
    case invalidChallenge

    var description: String {
        switch self {
        case let .analyticSphereUnavailable(capabilityID, capabilityVersion, snapshotVersion):
            "Analytic sphere capability \(capabilityID)@\(capabilityVersion) is unavailable in \(snapshotVersion)."
        case .unexpectedControllerResponse:
            "The production Agent capability request returned an unexpected response."
        case .invalidChallenge:
            "The capability observation received a non-sphere challenge."
        }
    }
}

/// The immutable production capability observation consumed by the reference
/// sphere candidate. No candidate action is inferred from this value.
@MainActor
struct CADSphereCapabilityObservation: Equatable, Sendable {
    static let snapshotVersion = "agent-capabilities.v1"
    static let sphereIngressNames: Set<String> = [
        "createAnalyticSphere",
        "createSphere",
    ]

    let challenge: CADChallenge
    let snapshot: CADCapabilitySnapshot
    let observedAgentCapabilityNames: [String]
    let requestCount: Int

    var status: CADCapabilityStatus {
        snapshot.status(for: challenge.requiredCapability) ?? CADCapabilityStatus(
            id: challenge.requiredCapability.id,
            version: challenge.requiredCapability.version,
            available: false,
            reasonCode: "not-observed"
        )
    }

    var isAvailable: Bool {
        status.available
    }

    var typedUnavailable: CADSphereCapabilityObservationError? {
        guard !isAvailable else { return nil }
        return .analyticSphereUnavailable(
            capabilityID: challenge.requiredCapability.id,
            capabilityVersion: challenge.requiredCapability.version,
            snapshotVersion: snapshot.version
        )
    }

    /// Classifies only the production descriptor names. This pure classifier
    /// is shared by request-context construction and live observation so a
    /// sphere capability cannot appear available in one path and absent in
    /// the other.
    static func capabilityStatus(
        for challenge: CADChallenge,
        descriptorNames: [String]
    ) -> CADCapabilityStatus {
        let exposed = descriptorNames.contains { sphereIngressNames.contains($0) }
        return CADCapabilityStatus(
            id: challenge.requiredCapability.id,
            version: challenge.requiredCapability.version,
            available: exposed,
            reasonCode: exposed ? nil : "not-exposed"
        )
    }

    static func observe(
        challenge: CADChallenge,
        controller: ProjectAgentCommandController
    ) async throws -> CADSphereCapabilityObservation {
        guard challenge.category == .sphere,
              challenge.requiredCapability.id == CADBenchmarkCategory.sphere.capabilityID else {
            throw CADSphereCapabilityObservationError.invalidChallenge
        }

        let response = await controller.handle(.capabilities)
        guard case let .capabilities(descriptors) = response else {
            throw CADSphereCapabilityObservationError.unexpectedControllerResponse
        }

        let names = descriptors.map(\.name).sorted()
        let snapshot = CADCapabilitySnapshot(
            version: Self.snapshotVersion,
            statuses: [Self.capabilityStatus(for: challenge, descriptorNames: names)]
        )
        try snapshot.validate()
        return CADSphereCapabilityObservation(
            challenge: challenge,
            snapshot: snapshot,
            observedAgentCapabilityNames: names,
            requestCount: 1
        )
    }

    func candidateContext() -> CADCandidateContext {
        CADCandidateContext(
            challenge: challenge,
            capabilities: snapshot,
            remainingRounds: challenge.budget.maximumRounds,
            remainingActions: challenge.budget.maximumActions
        )
    }
}
