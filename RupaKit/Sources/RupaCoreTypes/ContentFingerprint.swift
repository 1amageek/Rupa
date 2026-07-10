import Foundation

public struct ContentFingerprint: Codable, Hashable, Sendable {
    public let algorithm: String
    public let value: String

    public init(algorithm: String, value: String) throws {
        let algorithm = algorithm.trimmingCharacters(in: .whitespacesAndNewlines)
        let value = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !algorithm.isEmpty, !value.isEmpty else {
            throw EditorError(
                code: .commandInvalid,
                message: "Content fingerprints require non-empty algorithm and value fields."
            )
        }
        if algorithm.hasPrefix("sha256-") {
            let hexadecimal = value.utf8.allSatisfy { byte in
                (48...57).contains(byte) || (97...102).contains(byte)
            }
            guard value.utf8.count == 64, hexadecimal else {
                throw EditorError(
                    code: .commandInvalid,
                    message: "SHA-256 content fingerprints require 64 lowercase hexadecimal characters."
                )
            }
        }
        self.algorithm = algorithm
        self.value = value
    }

    public static func sha256(
        algorithm: String,
        data: Data
    ) throws -> ContentFingerprint {
        try ContentFingerprint(
            algorithm: algorithm,
            value: StableDigest.sha256Hex(for: data)
        )
    }

    private enum CodingKeys: String, CodingKey {
        case algorithm
        case value
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(
            algorithm: container.decode(String.self, forKey: .algorithm),
            value: container.decode(String.self, forKey: .value)
        )
    }
}
