import Foundation

/// A loopback-only endpoint for the live agent HTTP adapter.
public struct AgentHTTPEndpoint: Codable, Equatable, Sendable {
    public static let loopbackHost = "127.0.0.1"

    public let host: String
    public let port: UInt16

    public init(port: UInt16) throws {
        try self.init(host: Self.loopbackHost, port: port)
    }

    public init(host: String, port: UInt16) throws {
        guard host == Self.loopbackHost, port != 0 else {
            throw AgentHTTPError.invalidEndpoint
        }
        self.host = host
        self.port = port
    }
}
