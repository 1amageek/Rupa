import Foundation
import RupaCoreTypes

/// Package-owned, codec-produced CAD source bytes.
///
/// CAD syntax and semantic validation belong to the codec that creates or
/// consumes this value. The package boundary owns only entry identity and the
/// byte-preservation contract.
public struct ProjectPackageCADSource: Equatable, Sendable {
    public static let mediaType = "application/vnd.rupa.cad-source+json"
    public static let schemaVersion: UInt32 = 1
    public static let fingerprintAlgorithm = "sha256-rupa-cad-source-json-v1"

    public let data: Data
    public let sourceEntry: ProjectPackageSourceEntry

    public init(data: Data) throws {
        guard !data.isEmpty else {
            throw ProjectPackageError(
                code: .invalidSource,
                message: "Project CAD source bytes must not be empty."
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
                message: "Project CAD source identity is invalid: \(error)."
            )
        }
        self.data = data
        self.sourceEntry = try ProjectPackageSourceEntry(
            path: ProjectPackageManifest.cadSourcePath,
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
                message: "Project CAD source bytes do not match their declared entry."
            )
        }
        self = validated
    }
}
