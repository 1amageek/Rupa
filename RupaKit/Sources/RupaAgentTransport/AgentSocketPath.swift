import Foundation

public struct AgentSocketPath: Codable, Equatable, Sendable {
    public var value: String

    public init(_ value: String = AgentSocketPath.defaultPath) {
        self.value = value
    }

    /// Shared app-group container so the sandboxed app and unsandboxed CLI
    /// resolve the same socket location. Inside the sandbox,
    /// `temporaryDirectory` maps to the app container and is unreachable from
    /// external agent clients; the group container is the one location both
    /// sides can address.
    public static let appGroupIdentifier = "WWCKBW8CKN.team.stamp.rupa"

    public static var defaultPath: String {
        if let container = FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: appGroupIdentifier
        ) {
            return container
                .appendingPathComponent("rupa-agent", isDirectory: true)
                .appendingPathComponent("rupa.sock")
                .path
        }
        // Sandboxed processes without the app-group entitlement fall back to
        // their private temporary directory (previous behavior).
        return FileManager.default
            .temporaryDirectory
            .appendingPathComponent("rupa-agent", isDirectory: true)
            .appendingPathComponent("rupa.sock")
            .path
    }
}
