import Foundation

public struct ContentFingerprint: Codable, Hashable, Sendable {
    public let algorithm: String
    public let value: String

    public init(algorithm: String, value: String) throws {
        let trimmedAlgorithm = algorithm.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedValue = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedAlgorithm.isEmpty,
              !trimmedValue.isEmpty,
              trimmedAlgorithm == algorithm,
              trimmedValue == value,
              trimmedAlgorithm.utf8.count <= StableTypeValidation.maximumIdentifierByteCount,
              trimmedValue.utf8.count <= StableTypeValidation.maximumIdentifierByteCount,
              trimmedAlgorithm.unicodeScalars.allSatisfy({
                  !CharacterSet.controlCharacters.contains($0)
              }),
              trimmedValue.unicodeScalars.allSatisfy({
                  !CharacterSet.controlCharacters.contains($0)
              }) else {
            throw EditorError(
                code: .commandInvalid,
                message: "Content fingerprints require non-empty, unpadded, "
                    + "control-free, bounded algorithm and value fields."
            )
        }
        if trimmedAlgorithm.hasPrefix("sha256-") {
            let hexadecimal = trimmedValue.utf8.allSatisfy { byte in
                (48...57).contains(byte) || (97...102).contains(byte)
            }
            guard trimmedValue.utf8.count == 64, hexadecimal else {
                throw EditorError(
                    code: .commandInvalid,
                    message: "SHA-256 content fingerprints require 64 lowercase hexadecimal characters."
                )
            }
        }
        self.algorithm = trimmedAlgorithm
        self.value = trimmedValue
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
