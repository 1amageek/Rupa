import RupaCore
import RupaCoreTypes

public protocol DomainValidator: Sendable {
    var namespace: SemanticNamespaceID { get }

    func validate(
        envelope: SemanticExtensionEnvelope,
        in document: DesignDocument
    ) throws -> [EditorDiagnostic]
}
