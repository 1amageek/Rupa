import RupaCore

public protocol DomainPayloadDecoder: Sendable {
    var namespace: SemanticNamespaceID { get }

    func decode(_ envelope: SemanticExtensionEnvelope) throws -> DomainPayloadDecodingResult
}
