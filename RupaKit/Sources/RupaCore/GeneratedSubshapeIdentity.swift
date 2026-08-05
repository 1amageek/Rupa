import Foundation
import SwiftCAD

/// Canonical string codec for generated-topology subshape identity.
///
/// The kernel's stable identity is `SubshapeID { featureID, role, ordinal }`.
/// Product surfaces that require a string identity (selection component IDs,
/// accessibility identifiers, deterministic sort keys) must use this codec so
/// every layer round-trips the same representation.
public enum GeneratedSubshapeIdentity {
    private static let separator: Character = "/"

    public static func string(for subshapeID: SubshapeID) -> String {
        "\(subshapeID.featureID.description)\(separator)\(subshapeID.role)\(separator)\(subshapeID.ordinal)"
    }

    public static func subshapeID(from string: String) -> SubshapeID? {
        let components = string.split(
            separator: separator,
            omittingEmptySubsequences: false
        )
        guard components.count == 3,
              let featureUUID = UUID(uuidString: String(components[0])),
              !components[1].isEmpty,
              let ordinal = Int(components[2]),
              ordinal >= 0 else {
            return nil
        }
        return SubshapeID(
            featureID: FeatureID(featureUUID),
            role: String(components[1]),
            ordinal: ordinal
        )
    }

    public static func requireSubshapeID(
        from string: String,
        operationName: String
    ) throws -> SubshapeID {
        guard let subshapeID = subshapeID(from: string) else {
            throw EditorError(
                code: .commandInvalid,
                message: "\(operationName) requires a valid generated topology subshape identity."
            )
        }
        return subshapeID
    }

    /// Deterministic ordering for user-facing lists and stable iteration.
    public static func areInIncreasingOrder(_ lhs: SubshapeID, _ rhs: SubshapeID) -> Bool {
        if lhs.featureID.description != rhs.featureID.description {
            return lhs.featureID.description < rhs.featureID.description
        }
        if lhs.role != rhs.role {
            return lhs.role < rhs.role
        }
        return lhs.ordinal < rhs.ordinal
    }
}
