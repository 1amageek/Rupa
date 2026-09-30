import RupaCoreTypes
import RupaProjectModel

/// Computes the semantic identity of the authoritative CAD source used by a
/// CAD-derived Authored Mesh provenance record.
public struct CADSourceContentIdentityService: Sendable {
    public init() {}

    public func identity(for document: DesignDocument) throws -> ContentIdentity {
        try identity(for: document.validate())
    }

    /// The identity of an already validated document, read from the source fingerprint its
    /// validated CAD document carries, so a caller holding the store's validation hashes nothing
    /// the evaluation already hashed.
    public func identity(for document: ValidatedDesignDocument) throws -> ContentIdentity {
        let fingerprint = try document.validatedCADDocument.sourceFingerprint()
        return try ContentIdentity(
            domain: AuthoredMeshProvenance.cadSourceIdentityDomain,
            fingerprint: ContentFingerprint(
                algorithm: fingerprint.algorithm,
                value: fingerprint.value
            )
        )
    }
}
