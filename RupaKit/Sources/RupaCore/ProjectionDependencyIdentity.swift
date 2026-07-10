import Foundation
import SwiftCAD
import RupaCoreTypes

public struct ProjectionDependencyIdentity: Codable, Hashable, Sendable {
    public var documentID: DocumentID
    public var generation: DocumentGeneration
    public var fingerprint: ContentFingerprint

    public init(
        documentID: DocumentID,
        generation: DocumentGeneration,
        fingerprint: ContentFingerprint
    ) {
        self.documentID = documentID
        self.generation = generation
        self.fingerprint = fingerprint
    }

    public func validate() throws {
        guard !fingerprint.algorithm.isEmpty, !fingerprint.value.isEmpty else {
            throw ReferenceValidationError(
                code: .invalidIdentity,
                message: "Projection dependency fingerprints must not be empty."
            )
        }
    }

    public func matchesDependencies(of other: ProjectionDependencyIdentity) -> Bool {
        documentID == other.documentID && fingerprint == other.fingerprint
    }
}
