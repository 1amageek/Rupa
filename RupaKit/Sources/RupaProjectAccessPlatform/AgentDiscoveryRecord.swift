import Foundation

public struct AgentDiscoveryRecord: Codable, Equatable, Sendable {
    public static let keyByteCount = 32

    public let port: UInt16
    public let generation: UInt64
    public let key: Data

    public init(port: UInt16, generation: UInt64, key: Data) throws {
        guard port != 0 else { throw AgentDiscoveryError.invalidPort }
        guard generation != 0 else { throw AgentDiscoveryError.invalidGeneration }
        guard key.count == Self.keyByteCount else {
            throw AgentDiscoveryError.invalidKeyLength(key.count)
        }
        self.port = port
        self.generation = generation
        self.key = key
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(
            port: container.decode(UInt16.self, forKey: .port),
            generation: container.decode(UInt64.self, forKey: .generation),
            key: container.decode(Data.self, forKey: .key)
        )
    }

    private enum CodingKeys: String, CodingKey {
        case port
        case generation
        case key
    }
}
