public struct DocumentContentIdentity: Codable, Hashable, Sendable {
    public static let domain = "rupa.document-source.v1"

    public let content: ContentIdentity

    public init(fingerprint: ContentFingerprint) throws {
        self.content = try ContentIdentity(
            domain: Self.domain,
            fingerprint: fingerprint
        )
    }

    private enum CodingKeys: String, CodingKey {
        case content
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let content = try container.decode(ContentIdentity.self, forKey: .content)
        guard content.domain == Self.domain else {
            throw EditorError(
                code: .commandInvalid,
                message: "Document content identities require the rupa.document-source.v1 domain."
            )
        }
        self.content = content
    }
}
