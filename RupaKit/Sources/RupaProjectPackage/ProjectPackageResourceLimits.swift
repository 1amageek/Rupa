import RupaGeometry

/// Bounds allocation, archive growth, and borrowed I/O for one project package.
public struct ProjectPackageResourceLimits: Equatable, Sendable {
    public static let standard: ProjectPackageResourceLimits = {
        var meshSource = MeshSourceCodecLimits.standard
        meshSource.maximumBlobByteCount = UInt64(UInt32.max)
        return ProjectPackageResourceLimits(
            maximumArchiveByteCount: UInt64(UInt32.max),
            maximumEntryCount: 4_096,
            maximumManifestByteCount: 4 * 1_024 * 1_024,
            maximumSourceMetadataByteCount: 64 * 1_024 * 1_024,
            maximumSourceBlobByteCount: UInt64(UInt32.max),
            maximumPreservedAdjunctByteCount: 1 * 1_024 * 1_024 * 1_024,
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
