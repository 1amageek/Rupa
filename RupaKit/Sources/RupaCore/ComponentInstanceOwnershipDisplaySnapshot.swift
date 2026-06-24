public struct ComponentInstanceOwnershipDisplaySnapshot: Codable, Equatable, Sendable {
    public enum Kind: String, Codable, Equatable, Sendable {
        case document
        case patternArrayOutput
    }

    public var kind: Kind
    public var patternArraySourceID: PatternArraySourceID?
    public var patternArraySourceName: String?
    public var patternArrayOutputIndex: Int?

    public var isDirectlyEditable: Bool {
        kind == .document
    }

    public static var document: ComponentInstanceOwnershipDisplaySnapshot {
        ComponentInstanceOwnershipDisplaySnapshot(
            kind: .document,
            patternArraySourceID: nil,
            patternArraySourceName: nil,
            patternArrayOutputIndex: nil
        )
    }

    public static func patternArrayOutput(
        sourceID: PatternArraySourceID,
        sourceName: String,
        outputIndex: Int
    ) -> ComponentInstanceOwnershipDisplaySnapshot {
        ComponentInstanceOwnershipDisplaySnapshot(
            kind: .patternArrayOutput,
            patternArraySourceID: sourceID,
            patternArraySourceName: sourceName,
            patternArrayOutputIndex: outputIndex
        )
    }

    private init(
        kind: Kind,
        patternArraySourceID: PatternArraySourceID?,
        patternArraySourceName: String?,
        patternArrayOutputIndex: Int?
    ) {
        self.kind = kind
        self.patternArraySourceID = patternArraySourceID
        self.patternArraySourceName = patternArraySourceName
        self.patternArrayOutputIndex = patternArrayOutputIndex
    }

    private enum CodingKeys: String, CodingKey {
        case kind
        case patternArraySourceID
        case patternArraySourceName
        case patternArrayOutputIndex
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let kind = try container.decode(Kind.self, forKey: .kind)
        switch kind {
        case .document:
            guard try container.decodeIfPresent(PatternArraySourceID.self, forKey: .patternArraySourceID) == nil,
                  try container.decodeIfPresent(String.self, forKey: .patternArraySourceName) == nil,
                  try container.decodeIfPresent(Int.self, forKey: .patternArrayOutputIndex) == nil else {
                throw DecodingError.dataCorruptedError(
                    forKey: .kind,
                    in: container,
                    debugDescription: "Document-owned component instances must not include pattern array ownership fields."
                )
            }
            self = .document
        case .patternArrayOutput:
            let sourceID = try container.decode(PatternArraySourceID.self, forKey: .patternArraySourceID)
            let sourceName = try container.decode(String.self, forKey: .patternArraySourceName)
            let outputIndex = try container.decode(Int.self, forKey: .patternArrayOutputIndex)
            guard outputIndex >= 0 else {
                throw DecodingError.dataCorruptedError(
                    forKey: .patternArrayOutputIndex,
                    in: container,
                    debugDescription: "Pattern array output indexes must be nonnegative."
                )
            }
            self = .patternArrayOutput(
                sourceID: sourceID,
                sourceName: sourceName,
                outputIndex: outputIndex
            )
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(kind, forKey: .kind)
        switch kind {
        case .document:
            return
        case .patternArrayOutput:
            try container.encode(patternArraySourceID, forKey: .patternArraySourceID)
            try container.encode(patternArraySourceName, forKey: .patternArraySourceName)
            try container.encode(patternArrayOutputIndex, forKey: .patternArrayOutputIndex)
        }
    }
}
