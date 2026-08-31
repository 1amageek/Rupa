public struct SemanticProgramSchemaVersion: Sendable, Equatable, Hashable, Comparable {
    public let major: UInt32
    public let minor: UInt32
    public let patch: UInt32

    public init(major: UInt32, minor: UInt32, patch: UInt32) {
        self.major = major
        self.minor = minor
        self.patch = patch
    }

    public static let current = SemanticProgramSchemaVersion(major: 1, minor: 0, patch: 0)

    public static func < (
        lhs: SemanticProgramSchemaVersion,
        rhs: SemanticProgramSchemaVersion
    ) -> Bool {
        if lhs.major != rhs.major { return lhs.major < rhs.major }
        if lhs.minor != rhs.minor { return lhs.minor < rhs.minor }
        return lhs.patch < rhs.patch
    }
}
