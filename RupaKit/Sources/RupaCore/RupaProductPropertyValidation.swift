import Foundation

func validateProperties(_ properties: [String: String], owner: String) throws {
    for key in properties.keys {
        guard !key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw RupaDocumentValidationError.invalidProductMetadata("\(owner) property keys must not be empty.")
        }
    }
}
