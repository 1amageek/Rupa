import Foundation
import RupaCoreTypes
import RupaGeometry

struct ProjectPackageArchiveEntrySource: MeshSourceChunkSource {
    private let data: Data
    private let entry: ProjectPackageArchiveEntryDescriptor
    private let maximumChunkByteCount: Int
    private var offset = 0
    private var hasher = StableSHA256Hasher()
    private var crc32 = ProjectPackageCRC32()
    private(set) var maximumReadChunkByteCount = 0

    init(
        backing: ProjectPackageArchiveBacking,
        entry: ProjectPackageArchiveEntryDescriptor,
        maximumChunkByteCount: Int
    ) {
        data = backing.data
        self.entry = entry
        self.maximumChunkByteCount = maximumChunkByteCount
    }

    mutating func read(into buffer: inout MutableSpan<UInt8>) throws -> Int {
        let remaining = entry.payloadRange.count - offset
        let copiedByteCount = min(buffer.count, maximumChunkByteCount, remaining)
        guard copiedByteCount > 0 else {
            return 0
        }
        try data.withUnsafeBytes { sourceBytes in
            try buffer.withUnsafeMutableBytes { destinationBytes in
                guard let baseAddress = sourceBytes.baseAddress else {
                    throw ProjectPackageError(
                        code: .ioFailure,
                        message: "Mapped project package storage is unavailable."
                    )
                }
                // Data retains the mapped owner and the codec owns the reusable
                // destination span. Both pointers remain inside this validated borrow.
                let source = UnsafeRawBufferPointer(
                    start: baseAddress.advanced(by: entry.payloadRange.lowerBound + offset),
                    count: copiedByteCount
                )
                destinationBytes.copyMemory(from: source)
                let typedSource = source.bindMemory(to: UInt8.self)
                let span = Span(_unsafeElements: typedSource)
                hasher.update(span)
                crc32.update(span)
            }
        }
        offset += copiedByteCount
        maximumReadChunkByteCount = max(maximumReadChunkByteCount, copiedByteCount)
        return copiedByteCount
    }

    func validateCompletion(against reference: ProjectSourceBlobReference) throws {
        guard offset == entry.payloadRange.count,
            UInt64(offset) == reference.byteCount,
            hasher.hexDigest() == reference.fingerprint.value,
            crc32.checksum == entry.checksum
        else {
            throw ProjectPackageError(
                code: .integrityMismatch,
                message: "Decoded mesh source integrity validation failed: \(entry.path)."
            )
        }
    }
}
