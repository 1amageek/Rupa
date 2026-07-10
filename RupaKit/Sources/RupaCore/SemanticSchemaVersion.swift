public struct SemanticSchemaVersion: Codable, Hashable, Sendable {
    public var major: Int
    public var minor: Int
    public var patch: Int

    public init(
        major: Int,
        minor: Int,
        patch: Int
    ) {
        self.major = major
        self.minor = minor
        self.patch = patch
    }

    public func validate() throws {
        guard major >= 0, minor >= 0, patch >= 0 else {
            throw DocumentValidationError.invalidProductMetadata(
                "Semantic schema versions must use non-negative components."
            )
        }
    }
}
