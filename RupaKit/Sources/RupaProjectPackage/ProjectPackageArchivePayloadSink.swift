import RupaGeometry

struct ProjectPackageArchivePayloadSink<Base: ProjectPackageByteSink>:
    ProjectPackageByteSink, MeshSourceChunkSink
{
    var base: Base
    private let expectedByteCount: UInt32
    private let expectedChecksum: UInt32
    private let maximumChunkByteCount: Int
    private var crc32 = ProjectPackageCRC32()
    private(set) var writtenByteCount: UInt64 = 0
    private(set) var maximumWrittenChunkByteCount = 0

    init(
        base: Base,
        expectedByteCount: UInt32,
        expectedChecksum: UInt32,
        maximumChunkByteCount: Int
    ) {
        self.base = base
        self.expectedByteCount = expectedByteCount
        self.expectedChecksum = expectedChecksum
        self.maximumChunkByteCount = maximumChunkByteCount
    }

    mutating func write(_ bytes: borrowing Span<UInt8>) throws {
        let addition = writtenByteCount.addingReportingOverflow(UInt64(bytes.count))
        guard !addition.overflow,
            addition.partialValue <= UInt64(expectedByteCount),
            bytes.count <= maximumChunkByteCount
        else {
            throw ProjectPackageError(
                code: .resourceLimitExceeded,
                message: "Project package entry exceeded its declared bounded payload."
            )
        }
        try base.write(bytes)
        crc32.update(bytes)
        writtenByteCount = addition.partialValue
        maximumWrittenChunkByteCount = max(maximumWrittenChunkByteCount, bytes.count)
    }

    func validateCompletion() throws {
        guard writtenByteCount == UInt64(expectedByteCount) else {
            throw ProjectPackageError(
                code: .integrityMismatch,
                message: "Project package entry length differs from its declaration."
            )
        }
        guard crc32.checksum == expectedChecksum else {
            throw ProjectPackageError(
                code: .integrityMismatch,
                message: "Project package entry checksum differs from its declaration."
            )
        }
    }
}
