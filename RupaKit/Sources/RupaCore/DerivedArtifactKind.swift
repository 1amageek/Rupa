public struct DerivedArtifactKind: RawRepresentable, Codable, Hashable, Sendable,
    ExpressibleByStringLiteral
{
    public let rawValue: String

    public init(rawValue: String) {
        self.rawValue = rawValue
    }

    public init(stringLiteral value: String) {
        self.init(rawValue: value)
    }

    public static let brep: DerivedArtifactKind = "rupa.artifact.brep"
    public static let mesh: DerivedArtifactKind = "rupa.artifact.mesh"
    public static let drawing: DerivedArtifactKind = "rupa.artifact.drawing"
    public static let validation: DerivedArtifactKind = "rupa.artifact.validation"
    public static let exchange: DerivedArtifactKind = "rupa.artifact.exchange"
    public static let solverInput: DerivedArtifactKind = "rupa.artifact.solverInput"
    public static let solverResult: DerivedArtifactKind = "rupa.artifact.solverResult"

    public func validate() throws {
        guard !rawValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw ReferenceValidationError(
                code: .invalidIdentity,
                message: "Artifact kinds must not be empty."
            )
        }
    }
}
