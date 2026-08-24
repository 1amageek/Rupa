/// Bounds memory, input size, and collection growth for one mesh-source frame.
public struct MeshSourceCodecLimits: Equatable, Sendable {
    public static let standard = MeshSourceCodecLimits(
        maximumBlobByteCount: 8 * 1_024 * 1_024 * 1_024,
        maximumChunkByteCount: 64 * 1_024,
        maximumElementCountPerBuffer: 100_000_000,
        maximumAttributeCount: 4_096,
        maximumStringByteCount: 1_048_576
    )

    public var maximumBlobByteCount: UInt64
    public var maximumChunkByteCount: Int
    public var maximumElementCountPerBuffer: Int
    public var maximumAttributeCount: Int
    public var maximumStringByteCount: Int

    public init(
        maximumBlobByteCount: UInt64,
        maximumChunkByteCount: Int,
        maximumElementCountPerBuffer: Int,
        maximumAttributeCount: Int,
        maximumStringByteCount: Int
    ) {
        self.maximumBlobByteCount = maximumBlobByteCount
        self.maximumChunkByteCount = maximumChunkByteCount
        self.maximumElementCountPerBuffer = maximumElementCountPerBuffer
        self.maximumAttributeCount = maximumAttributeCount
        self.maximumStringByteCount = maximumStringByteCount
    }

    func validate() throws {
        guard maximumBlobByteCount >= MeshSourceBinaryFormat.headerByteCount,
            maximumChunkByteCount > 0,
            maximumElementCountPerBuffer >= 0,
            maximumAttributeCount >= 0,
            maximumStringByteCount >= 0
        else {
            throw MeshSourceError(
                code: .resourceLimitExceeded,
                message:
                    "Mesh source codec limits must be non-negative and provide a non-empty chunk."
            )
        }
    }
}
