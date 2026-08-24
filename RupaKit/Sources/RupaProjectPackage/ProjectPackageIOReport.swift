import RupaGeometry

public struct ProjectPackageIOReport: Equatable, Sendable {
    public let archiveByteCount: UInt64
    public let encodedSourceBlobCount: Int
    public let encodedSourceBlobByteCount: UInt64
    public let reusedSourceBlobCount: Int
    public let reusedSourceBlobByteCount: UInt64
    public let preservedAdjunctCount: Int
    public let preservedAdjunctByteCount: UInt64
    public let maximumReadChunkByteCount: Int
    public let maximumWriteChunkByteCount: Int
    public let geometryCopyTelemetry: GeometryCopyTelemetry

    public init(
        archiveByteCount: UInt64,
        encodedSourceBlobCount: Int,
        encodedSourceBlobByteCount: UInt64,
        reusedSourceBlobCount: Int,
        reusedSourceBlobByteCount: UInt64,
        preservedAdjunctCount: Int,
        preservedAdjunctByteCount: UInt64,
        maximumReadChunkByteCount: Int,
        maximumWriteChunkByteCount: Int,
        geometryCopyTelemetry: GeometryCopyTelemetry
    ) {
        self.archiveByteCount = archiveByteCount
        self.encodedSourceBlobCount = encodedSourceBlobCount
        self.encodedSourceBlobByteCount = encodedSourceBlobByteCount
        self.reusedSourceBlobCount = reusedSourceBlobCount
        self.reusedSourceBlobByteCount = reusedSourceBlobByteCount
        self.preservedAdjunctCount = preservedAdjunctCount
        self.preservedAdjunctByteCount = preservedAdjunctByteCount
        self.maximumReadChunkByteCount = maximumReadChunkByteCount
        self.maximumWriteChunkByteCount = maximumWriteChunkByteCount
        self.geometryCopyTelemetry = geometryCopyTelemetry
    }
}
