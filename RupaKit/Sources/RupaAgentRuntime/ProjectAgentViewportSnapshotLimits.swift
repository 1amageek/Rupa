import RupaKit

/// Fixed semantic ceilings for one exact viewport summary projection.
struct ProjectAgentViewportSnapshotLimits: Equatable, Sendable {
    static let hardMaximum = ProjectAgentViewportSnapshotLimits(
        maxItems: 4_096,
        maxElementRecords: 1_048_576,
        maxAuxiliaryRecords: 4_096,
        maxTriangleCount: 1_048_576,
        maxStringUTF8Bytes: 1_048_576
    )

    static let standard = hardMaximum

    let maxItems: Int
    let maxElementRecords: Int
    let maxAuxiliaryRecords: Int
    let maxTriangleCount: UInt64
    let maxStringUTF8Bytes: Int

    init(
        maxItems: Int,
        maxElementRecords: Int,
        maxAuxiliaryRecords: Int,
        maxTriangleCount: UInt64,
        maxStringUTF8Bytes: Int
    ) {
        self.maxItems = maxItems
        self.maxElementRecords = maxElementRecords
        self.maxAuxiliaryRecords = maxAuxiliaryRecords
        self.maxTriangleCount = maxTriangleCount
        self.maxStringUTF8Bytes = maxStringUTF8Bytes
    }

    func validate() throws {
        guard maxItems > 0,
              maxElementRecords > 0,
              maxAuxiliaryRecords > 0,
              maxTriangleCount > 0,
              maxStringUTF8Bytes > 0 else {
            throw ProjectMeshReadError(
                code: .invalidLimit,
                message: "Project viewport snapshot limits must be positive."
            )
        }
        let hard = Self.hardMaximum
        guard maxItems <= hard.maxItems,
              maxElementRecords <= hard.maxElementRecords,
              maxAuxiliaryRecords <= hard.maxAuxiliaryRecords,
              maxTriangleCount <= hard.maxTriangleCount,
              maxStringUTF8Bytes <= hard.maxStringUTF8Bytes else {
            throw ProjectMeshReadError(
                code: .limitExceeded,
                message: "Project viewport snapshot limits must not exceed the hard ceiling."
            )
        }
    }
}
