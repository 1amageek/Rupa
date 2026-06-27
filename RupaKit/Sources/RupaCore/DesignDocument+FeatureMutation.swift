import Foundation
import SwiftCAD
import RupaCoreTypes

extension DesignDocument {
    mutating func appendFeature(_ feature: FeatureNode) throws {
        try cadDocument.appendFeature(feature)
    }

    func normalizedMetadataName(
        _ name: String,
        owner: String
    ) throws -> String {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else {
            throw EditorError(
                code: .commandInvalid,
                message: "\(owner) names must not be empty."
            )
        }
        return trimmedName
    }
}
