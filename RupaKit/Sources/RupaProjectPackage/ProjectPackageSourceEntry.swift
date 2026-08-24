import RupaCoreTypes

public struct ProjectPackageSourceEntry: Codable, Equatable, Hashable, Sendable {
    public let path: String
    public let mediaType: String
    public let schemaVersion: UInt32
    public let byteCount: UInt64
    public let fingerprint: ContentFingerprint

    public init(
        path: String,
        mediaType: String,
        schemaVersion: UInt32,
        byteCount: UInt64,
        fingerprint: ContentFingerprint
    ) throws {
        try ProjectPackageEntryPath.validateSourcePath(path)
        try Self.validateMediaType(mediaType)
        guard schemaVersion > 0, byteCount > 0,
            fingerprint.algorithm.hasPrefix("sha256-")
        else {
            throw ProjectPackageError(
                code: .invalidManifest,
                message: "Project source entries require a positive schema and size plus SHA-256 identity."
            )
        }
        self.path = path
        self.mediaType = mediaType
        self.schemaVersion = schemaVersion
        self.byteCount = byteCount
        self.fingerprint = fingerprint
    }

    private enum CodingKeys: String, CodingKey {
        case path
        case mediaType
        case schemaVersion
        case byteCount
        case fingerprint
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(
            path: container.decode(String.self, forKey: .path),
            mediaType: container.decode(String.self, forKey: .mediaType),
            schemaVersion: container.decode(UInt32.self, forKey: .schemaVersion),
            byteCount: container.decode(UInt64.self, forKey: .byteCount),
            fingerprint: container.decode(ContentFingerprint.self, forKey: .fingerprint)
        )
    }

    private static func validateMediaType(_ mediaType: String) throws {
        let parts = mediaType.split(separator: "/", omittingEmptySubsequences: false)
        let isValidByte: (UInt8) -> Bool = { byte in
            (48...57).contains(byte)
                || (65...90).contains(byte)
                || (97...122).contains(byte)
                || byte == 0x2B
                || byte == 0x2D
                || byte == 0x2E
        }
        guard mediaType.utf8.count <= 256,
            parts.count == 2,
            parts.allSatisfy({ !$0.isEmpty && $0.utf8.allSatisfy(isValidByte) })
        else {
            throw ProjectPackageError(
                code: .invalidManifest,
                message: "Project source media types must be bounded canonical type/subtype values."
            )
        }
    }
}
