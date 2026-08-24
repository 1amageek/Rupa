import RupaCoreTypes

public struct ProjectSourceBlobReference: Codable, Equatable, Hashable, Sendable {
    public static let pathPrefix = "source/blobs/sha256/"

    public let path: String
    public let mediaType: String
    public let schemaVersion: UInt32
    public let byteCount: UInt64
    public let fingerprint: ContentFingerprint

    public init(entry: ProjectPackageSourceEntry) throws {
        guard entry.path.hasPrefix(Self.pathPrefix),
            String(entry.path.dropFirst(Self.pathPrefix.count)) == entry.fingerprint.value
        else {
            throw ProjectPackageError(
                code: .invalidManifest,
                message: "Project source blob paths must equal their SHA-256 content identity."
            )
        }
        self.path = entry.path
        self.mediaType = entry.mediaType
        self.schemaVersion = entry.schemaVersion
        self.byteCount = entry.byteCount
        self.fingerprint = entry.fingerprint
    }

    public init(
        mediaType: String,
        schemaVersion: UInt32,
        byteCount: UInt64,
        fingerprint: ContentFingerprint
    ) throws {
        try self.init(
            entry: ProjectPackageSourceEntry(
                path: Self.pathPrefix + fingerprint.value,
                mediaType: mediaType,
                schemaVersion: schemaVersion,
                byteCount: byteCount,
                fingerprint: fingerprint
            )
        )
    }

    public var sourceEntry: ProjectPackageSourceEntry {
        get throws {
            try ProjectPackageSourceEntry(
                path: path,
                mediaType: mediaType,
                schemaVersion: schemaVersion,
                byteCount: byteCount,
                fingerprint: fingerprint
            )
        }
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
        let entry = try ProjectPackageSourceEntry(
            path: container.decode(String.self, forKey: .path),
            mediaType: container.decode(String.self, forKey: .mediaType),
            schemaVersion: container.decode(UInt32.self, forKey: .schemaVersion),
            byteCount: container.decode(UInt64.self, forKey: .byteCount),
            fingerprint: container.decode(ContentFingerprint.self, forKey: .fingerprint)
        )
        try self.init(entry: entry)
    }
}
