import Foundation

public struct AgentSocketPath: Codable, Equatable, Sendable {
    public var value: String

    public init(_ value: String = AgentSocketPath.defaultPath) {
        self.value = value
    }

    public static var defaultPath: String {
        FileManager.default
            .temporaryDirectory
            .appendingPathComponent("rupa-agent", isDirectory: true)
            .appendingPathComponent("rupa.sock")
            .path
    }
}
