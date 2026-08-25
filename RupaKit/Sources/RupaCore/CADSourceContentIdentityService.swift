import RupaCoreTypes
import RupaProjectModel

/// Computes the semantic identity of the authoritative CAD source used by a
/// CAD-derived Authored Mesh provenance record.
public struct CADSourceContentIdentityService: Sendable {
    public init() {}

    public func identity(for document: DesignDocument) throws -> ContentIdentity {
        let validated = try document.validate()
        let fingerprint = try validated.validatedCADDocument.sourceFingerprint()
        return try ContentIdentity(
            domain: AuthoredMeshProvenance.cadSourceIdentityDomain,
            fingerprint: ContentFingerprint(
                algorithm: fingerprint.algorithm,
                value: fingerprint.value
            )
        )
    }
}
