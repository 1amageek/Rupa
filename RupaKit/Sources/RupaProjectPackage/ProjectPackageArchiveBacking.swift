import Foundation
import RupaCoreTypes

struct ProjectPackageArchiveBacking: Sendable {
    let data: Data
    let entries: [String: ProjectPackageArchiveEntryDescriptor]

    func materialize(
        _ entry: ProjectPackageArchiveEntryDescriptor,
        maximumByteCount: Int
    ) throws -> Data {
        guard entry.payloadRange.count <= maximumByteCount else {
            throw ProjectPackageError(
                code: .resourceLimitExceeded,
                message: "Project package metadata exceeds its configured limit."
            )
        }
        // Product, CAD, and Mesh-catalog codecs consume owning Data at this single,
        // bounded materialization boundary. Mesh payloads never call this method
        // and remain mapped owner-plus-range values.
        return data.subdata(in: entry.payloadRange)
    }

    func validate(
        _ entry: ProjectPackageArchiveEntryDescriptor,
        against sourceEntry: ProjectPackageSourceEntry,
        maximumChunkByteCount: Int
    ) throws -> Int {
        guard UInt64(entry.byteCount) == sourceEntry.byteCount else {
            throw ProjectPackageError(
                code: .integrityMismatch,
                message: "Project package entry length differs from its manifest: \(entry.path)."
            )
        }
        var hasher = StableSHA256Hasher()
        var crc32 = ProjectPackageCRC32()
        var maximumObservedChunkByteCount = 0
        try withPayloadChunks(
            entry,
            maximumChunkByteCount: maximumChunkByteCount
        ) { chunk in
            hasher.update(chunk)
            crc32.update(chunk)
            maximumObservedChunkByteCount = max(maximumObservedChunkByteCount, chunk.count)
        }
        guard hasher.hexDigest() == sourceEntry.fingerprint.value,
            crc32.checksum == entry.checksum
        else {
            throw ProjectPackageError(
                code: .integrityMismatch,
                message: "Project package entry integrity validation failed: \(entry.path)."
            )
        }
        return maximumObservedChunkByteCount
    }

    func validateChecksum(
        _ entry: ProjectPackageArchiveEntryDescriptor,
        maximumChunkByteCount: Int
    ) throws -> Int {
        var crc32 = ProjectPackageCRC32()
        var maximumObservedChunkByteCount = 0
        try withPayloadChunks(
            entry,
            maximumChunkByteCount: maximumChunkByteCount
        ) { chunk in
            crc32.update(chunk)
            maximumObservedChunkByteCount = max(maximumObservedChunkByteCount, chunk.count)
        }
        guard crc32.checksum == entry.checksum else {
            throw ProjectPackageError(
                code: .integrityMismatch,
                message: "Project package entry checksum validation failed: \(entry.path)."
            )
        }
        return maximumObservedChunkByteCount
    }

    func copy<Base: ProjectPackageByteSink>(
        _ entry: ProjectPackageArchiveEntryDescriptor,
        to sink: inout ProjectPackageArchivePayloadSink<Base>,
        maximumChunkByteCount: Int
    ) throws {
        try withPayloadChunks(
            entry,
            maximumChunkByteCount: maximumChunkByteCount
        ) { chunk in
            try sink.write(chunk)
        }
    }

    private func withPayloadChunks(
        _ entry: ProjectPackageArchiveEntryDescriptor,
        maximumChunkByteCount: Int,
        _ body: (borrowing Span<UInt8>) throws -> Void
    ) throws {
        guard maximumChunkByteCount > 0 else {
            throw ProjectPackageError(
                code: .resourceLimitExceeded,
                message: "Project package chunk size must be positive."
            )
        }
        try data.withUnsafeBytes { rawBytes in
            // Data retains the immutable mapped owner. The span covers a validated
            // payload range, remains inside this synchronous borrow, and never escapes.
            let pointer = rawBytes.bindMemory(to: UInt8.self)
            let fullSpan = Span(_unsafeElements: pointer)
            var offset = entry.payloadRange.lowerBound
            while offset < entry.payloadRange.upperBound {
                let remainingByteCount = entry.payloadRange.upperBound - offset
                let upperBound = offset + min(remainingByteCount, maximumChunkByteCount)
                try body(fullSpan.extracting(offset..<upperBound))
                offset = upperBound
            }
        }
    }
}
