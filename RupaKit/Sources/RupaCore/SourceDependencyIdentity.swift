import RupaCoreTypes

public struct SourceDependencyIdentity: Codable, Hashable, Sendable {
    public let subject: SourceDependencySubject
    public let contentFingerprint: ContentFingerprint

    public init(
        subject: SourceDependencySubject,
        contentFingerprint: ContentFingerprint
    ) throws {
        try subject.validate()
        self.subject = subject
        self.contentFingerprint = contentFingerprint
    }

    private enum CodingKeys: String, CodingKey {
        case subject
        case contentFingerprint
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(
            subject: container.decode(SourceDependencySubject.self, forKey: .subject),
            contentFingerprint: container.decode(ContentFingerprint.self, forKey: .contentFingerprint)
        )
    }
}
