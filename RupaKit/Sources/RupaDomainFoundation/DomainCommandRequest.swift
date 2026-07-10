import RupaCore
import RupaCoreTypes

public struct DomainCommandRequest: Codable, Equatable, Sendable {
    public var capabilityID: DomainCapabilityID
    public var namespace: SemanticNamespaceID
    public var payload: SemanticJSONValue
    public var expectedGeneration: DocumentGeneration?
    public var dryRun: Bool

    public init(
        capabilityID: DomainCapabilityID,
        namespace: SemanticNamespaceID,
        payload: SemanticJSONValue,
        expectedGeneration: DocumentGeneration? = nil,
        dryRun: Bool = false
    ) {
        self.capabilityID = capabilityID
        self.namespace = namespace
        self.payload = payload
        self.expectedGeneration = expectedGeneration
        self.dryRun = dryRun
    }
}
