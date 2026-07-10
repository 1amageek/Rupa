import RupaCore
import RupaCoreTypes

public struct DomainProjectionRepairRequest: Sendable {
    public var envelope: SemanticExtensionEnvelope
    public var currentGeneration: DocumentGeneration?
    public var dryRun: Bool

    public init(
        envelope: SemanticExtensionEnvelope,
        currentGeneration: DocumentGeneration? = nil,
        dryRun: Bool = false
    ) {
        self.envelope = envelope
        self.currentGeneration = currentGeneration
        self.dryRun = dryRun
    }
}

public protocol DomainProjectionRepairProvider: Sendable {
    var namespace: SemanticNamespaceID { get }

    func repairProjection(_ request: DomainProjectionRepairRequest) throws -> DomainCommandPlan
}
