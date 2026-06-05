import Foundation
import SwiftCAD

public struct RupaMaterialLibrary: Codable, Hashable, Sendable {
    public var materials: [MaterialID: Material]
    public var defaultMaterialID: MaterialID?

    public init(
        materials: [MaterialID: Material] = [:],
        defaultMaterialID: MaterialID? = nil
    ) {
        self.materials = materials
        self.defaultMaterialID = defaultMaterialID
    }

    public func validate() throws {
        if let defaultMaterialID {
            guard materials[defaultMaterialID] != nil else {
                throw RupaDocumentValidationError.invalidProductMetadata(
                    "Default material must reference a material in the document material library."
                )
            }
        }

        var names: Set<String> = []
        for (materialID, material) in materials {
            guard material.id == materialID else {
                throw RupaDocumentValidationError.invalidProductMetadata(
                    "Material library keys must match material IDs."
                )
            }
            let trimmedName = material.name.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmedName.isEmpty else {
                throw RupaDocumentValidationError.invalidProductMetadata("Material names must not be empty.")
            }
            guard names.insert(trimmedName).inserted else {
                throw RupaDocumentValidationError.invalidProductMetadata(
                    "Material names must be unique within a document."
                )
            }
            try material.validate()
        }
    }
}
