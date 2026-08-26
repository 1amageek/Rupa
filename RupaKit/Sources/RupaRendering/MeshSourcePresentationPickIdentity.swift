import RupaCoreTypes

/// A presentation-only pick identity. It is allocated from scene occurrence
/// order and intentionally carries no modeling identity.
public struct MeshSourcePresentationPickIdentity: RawRepresentable, Hashable, Sendable {
    public let rawValue: UInt32

    public init?(rawValue: UInt32) {
        guard rawValue != 0 else {
            return nil
        }
        self.rawValue = rawValue
    }

    public init(ordinal: Int) throws {
        guard ordinal >= 0 else {
            throw MeshSourcePresentationPickError(
                code: .invalidIdentity,
                message: "Presentation pick identity ordinals must not be negative."
            )
        }
        let rawValue = UInt64(ordinal).addingReportingOverflow(1)
        guard !rawValue.overflow,
              rawValue.partialValue <= UInt64(UInt32.max) else {
            throw MeshSourcePresentationPickError(
                code: .identityOverflow,
                message: "Presentation pick identity allocation exceeded UInt32 capacity."
            )
        }
        self.rawValue = UInt32(rawValue.partialValue)
    }
}
