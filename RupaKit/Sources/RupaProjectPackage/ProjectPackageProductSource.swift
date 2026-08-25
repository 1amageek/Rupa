import Foundation
import RupaCoreTypes

/// Package-owned, codec-produced Product source bytes.
///
/// Product syntax and semantic validation belong to the codec that creates or
/// consumes this value. The package boundary owns only entry identity and the
/// byte-preservation contract.
public struct ProjectPackageProductSource: Equatable, Sendable {
    public static let mediaType = "application/vnd.rupa.product-source+json"
    public static let schemaVersion: UInt32 = 1
    public static let fingerprintAlgorithm = "sha256-rupa-product-source-json-v1"

    public let data: Data
    public let sourceEntry: ProjectPackageSourceEntry

    public init(data: Data) throws {
        guard data.isEmpty == false else {
            throw ProjectPackageError(
                code: .invalidSource,
                message: "Project Product source bytes must not be empty."
            )
        }
        let fingerprint: ContentFingerprint
        do {
            fingerprint = try .sha256(
                algorithm: Self.fingerprintAlgorithm,
                data: data
            )
        } catch {
            throw ProjectPackageError(
                code: .invalidSource,
                message: "Project Product source identity is invalid: \(error)."
            )
        }
        self.data = data
        self.sourceEntry = try ProjectPackageSourceEntry(
            path: ProjectPackageManifest.productSourcePath,
            mediaType: Self.mediaType,
            schemaVersion: Self.schemaVersion,
            byteCount: UInt64(data.count),
            fingerprint: fingerprint
        )
    }

    init(
        data: Data,
        declaredEntry: ProjectPackageSourceEntry
    ) throws {
        let validated = try Self(data: data)
        guard validated.sourceEntry == declaredEntry else {
            throw ProjectPackageError(
                code: .integrityMismatch,
                message: "Project Product source bytes do not match their declared entry."
            )
        }
        self = validated
    }
}
