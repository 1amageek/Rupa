public struct DesignProcessTestReference: Codable, Equatable, Sendable {
    public var target: String
    public var suite: String?
    public var name: String
    public var command: String?
    public var file: String?

    public init(
        target: String,
        suite: String? = nil,
        name: String,
        command: String? = nil,
        file: String? = nil
    ) {
        self.target = target
        self.suite = suite
        self.name = name
        self.command = command
        self.file = file
    }
}
