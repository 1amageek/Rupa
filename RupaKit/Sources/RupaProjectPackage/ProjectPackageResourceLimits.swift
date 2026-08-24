import RupaGeometry

/// Bounds allocation, archive growth, and borrowed I/O for one project package.
public struct ProjectPackageResourceLimits: Equatable, Sendable {
    public static let standard: ProjectPackageResourceLimits = {
        let archiveLimit = min(UInt64(UInt32.max), UInt64(Int.max))
        var meshSource = MeshSourceCodecLimits.standard
        meshSource.maximumBlobByteCount = archiveLimit
        return ProjectPackageResourceLimits(
            maximumArchiveByteCount: archiveLimit,
            maximumEntryCount: 4_096,
            maximumManifestByteCount: 4 * 1_024 * 1_024,
            maximumSourceMetadataByteCount: 64 * 1_024 * 1_024,
            maximumSourceBlobByteCount: archiveLimit,
            maximumPreservedAdjunctByteCount: min(
                archiveLimit,
                1 * 1_024 * 1_024 * 1_024
            ),
            maximumChunkByteCount: 64 * 1_024,
            meshSource: meshSource
        )
    }()

    public var maximumArchiveByteCount: UInt64
    public var maximumEntryCount: Int
    public var maximumManifestByteCount: Int
    public var maximumSourceMetadataByteCount: Int
    public var maximumSourceBlobByteCount: UInt64
    public var maximumPreservedAdjunctByteCount: UInt64
    public var maximumChunkByteCount: Int
    public var meshSource: MeshSourceCodecLimits

    public init(
        maximumArchiveByteCount: UInt64,
        maximumEntryCount: Int,
        maximumManifestByteCount: Int,
        maximumSourceMetadataByteCount: Int,
        maximumSourceBlobByteCount: UInt64,
        maximumPreservedAdjunctByteCount: UInt64,
        maximumChunkByteCount: Int,
        meshSource: MeshSourceCodecLimits
    ) {
        self.maximumArchiveByteCount = maximumArchiveByteCount
        self.maximumEntryCount = maximumEntryCount
        self.maximumManifestByteCount = maximumManifestByteCount
        self.maximumSourceMetadataByteCount = maximumSourceMetadataByteCount
        self.maximumSourceBlobByteCount = maximumSourceBlobByteCount
        self.maximumPreservedAdjunctByteCount = maximumPreservedAdjunctByteCount
        self.maximumChunkByteCount = maximumChunkByteCount
        self.meshSource = meshSource
    }

    func validate() throws {
        guard maximumArchiveByteCount > 0,
            maximumArchiveByteCount <= UInt64(UInt32.max),
            maximumEntryCount > 0,
            maximumEntryCount <= Int(UInt16.max),
            maximumManifestByteCount > 0,
            maximumSourceMetadataByteCount > 0,
            maximumSourceBlobByteCount > 0,
            maximumSourceBlobByteCount <= UInt64(UInt32.max),
            maximumChunkByteCount > 0,
            UInt64(maximumManifestByteCount) <= maximumArchiveByteCount,
            UInt64(maximumSourceMetadataByteCount) <= maximumArchiveByteCount,
            maximumSourceBlobByteCount <= maximumArchiveByteCount,
            maximumPreservedAdjunctByteCount <= maximumArchiveByteCount,
            UInt64(maximumChunkByteCount) <= maximumArchiveByteCount,
            meshSource.maximumBlobByteCount > 0,
            meshSource.maximumChunkByteCount > 0,
            meshSource.maximumElementCountPerBuffer >= 0,
            meshSource.maximumAttributeCount >= 0,
            meshSource.maximumStringByteCount >= 0,
            meshSource.maximumBlobByteCount <= maximumSourceBlobByteCount,
            meshSource.maximumChunkByteCount <= maximumChunkByteCount
        else {
            throw ProjectPackageError(
                code: .resourceLimitExceeded,
                message: "Project package limits are invalid for the version 1 archive contract."
            )
        }
    }
}
