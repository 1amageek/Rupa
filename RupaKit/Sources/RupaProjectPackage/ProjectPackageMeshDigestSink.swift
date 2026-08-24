import RupaCoreTypes
import RupaGeometry

struct ProjectPackageMeshDigestSink: MeshSourceChunkSink {
    static let mediaType = "application/vnd.rupa.mesh-source"
    static let schemaVersion: UInt32 = 1
    static let fingerprintAlgorithm = "sha256-rupa-mesh-source-v1"

    private let maximumByteCount: UInt64
    private var hasher = StableSHA256Hasher()
    private var crc32 = ProjectPackageCRC32()
    private(set) var byteCount: UInt64 = 0
    private(set) var maximumChunkByteCount = 0

    init(maximumByteCount: UInt64) {
        self.maximumByteCount = maximumByteCount
    }

    mutating func write(_ chunk: borrowing Span<UInt8>) throws {
        let addition = byteCount.addingReportingOverflow(UInt64(chunk.count))
        guard !addition.overflow, addition.partialValue <= maximumByteCount else {
            throw ProjectPackageError(
                code: .resourceLimitExceeded,
                message: "Encoded mesh source exceeds the configured package blob limit."
            )
        }
        hasher.update(chunk)
        crc32.update(chunk)
        byteCount = addition.partialValue
        maximumChunkByteCount = max(maximumChunkByteCount, chunk.count)
    }

    var checksum: UInt32 {
        crc32.checksum
    }

    func reference() throws -> ProjectSourceBlobReference {
        guard byteCount > 0 else {
            throw ProjectPackageError(
                code: .invalidSource,
                message: "Encoded mesh source must not be empty."
            )
        }
        do {
            return try ProjectSourceBlobReference(
                mediaType: Self.mediaType,
                schemaVersion: Self.schemaVersion,
                byteCount: byteCount,
                fingerprint: ContentFingerprint(
                    algorithm: Self.fingerprintAlgorithm,
                    value: hasher.hexDigest()
                )
            )
        } catch {
            throw ProjectPackageError(
                code: .invalidSource,
                message: "Encoded mesh source identity is invalid: \(error)."
            )
        }
    }
}
