public struct OffsetCurveOptions: Codable, Equatable, Sendable {
    public var mode: OffsetCurveMode
    public var isSymmetric: Bool
    public var gapFill: OffsetCurveGapFill
    public var supportTarget: SelectionTarget?

    public init(
        mode: OffsetCurveMode = .offset,
        isSymmetric: Bool = false,
        gapFill: OffsetCurveGapFill = .round,
        supportTarget: SelectionTarget? = nil
    ) {
        self.mode = mode
        self.isSymmetric = isSymmetric
        self.gapFill = gapFill
        self.supportTarget = supportTarget
    }

    private enum CodingKeys: String, CodingKey {
        case mode
        case isSymmetric
        case gapFill
        case supportTarget
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        mode = try container.decodeIfPresent(OffsetCurveMode.self, forKey: .mode) ?? .offset
        isSymmetric = try container.decodeIfPresent(Bool.self, forKey: .isSymmetric) ?? false
        gapFill = try container.decodeIfPresent(OffsetCurveGapFill.self, forKey: .gapFill) ?? .round
        supportTarget = try container.decodeIfPresent(SelectionTarget.self, forKey: .supportTarget)
    }
}
