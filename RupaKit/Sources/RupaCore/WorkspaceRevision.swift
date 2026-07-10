public struct WorkspaceRevision: Codable, Hashable, Sendable, Comparable {
    public let value: UInt64

    public init(_ value: UInt64 = 0) {
        self.value = value
    }

    public func advanced() throws -> WorkspaceRevision {
        let (value, overflow) = value.addingReportingOverflow(1)
        guard !overflow else {
            throw EditorError(
                code: .commandInvalid,
                message: "Workspace revision overflowed."
            )
        }
        return WorkspaceRevision(value)
    }

    public static func < (lhs: WorkspaceRevision, rhs: WorkspaceRevision) -> Bool {
        lhs.value < rhs.value
    }
}
