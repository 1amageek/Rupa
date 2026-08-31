import Foundation

enum AgentSemanticCoding {
    static func rejectUnknownKeys(
        from decoder: Decoder,
        allowedKeys: Set<String>
    ) throws {
        let container = try decoder.container(keyedBy: AgentSemanticAnyCodingKey.self)
        let unknownKeys = Set(container.allKeys.map(\.stringValue)).subtracting(allowedKeys)
        guard unknownKeys.isEmpty else {
            throw DecodingError.dataCorrupted(
                DecodingError.Context(
                    codingPath: decoder.codingPath,
                    debugDescription: "Unsupported semantic fields: \(unknownKeys.sorted().joined(separator: ", "))."
                )
            )
        }
    }
}

private struct AgentSemanticAnyCodingKey: CodingKey, Hashable {
    let stringValue: String
    let intValue: Int?

    init?(stringValue: String) {
        self.stringValue = stringValue
        self.intValue = nil
    }

    init?(intValue: Int) {
        self.stringValue = String(intValue)
        self.intValue = intValue
    }
}
