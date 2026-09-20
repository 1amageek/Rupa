import Foundation
import SwiftCAD
import RupaCoreTypes

extension DesignDocument {

    // MARK: - Node appearance

    /// Applies one appearance component to the material `id` names, creating and
    /// assigning that material when the node names none.
    ///
    /// Creating and assigning cannot be two commands sharing one transaction,
    /// because a transaction fixes its commands before the first one runs and
    /// nothing outside Core can name an identifier Core has yet to mint. The
    /// material this creates starts from `Material.neutral` and does not become
    /// the document default. See `RupaCore/DESIGN.md`.
    @discardableResult
    public mutating func setSceneNodeAppearance(
        id: SceneNodeID,
        edit: MaterialComponentEdit,
        objectRegistry: ObjectTypeRegistry = .builtIn
    ) throws -> MaterialID {
        guard let node = productMetadata.sceneNodes[id] else {
            throw EditorError(
                code: .referenceUnresolved,
                message: "Scene node appearance requires an existing scene node."
            )
        }
        guard PatternArrayOwnershipResolver().sourceID(
            containingGeneratedOutputSceneNode: id,
            in: productMetadata
        ) == nil else {
            throw EditorError(
                code: .commandInvalid,
                message: "Pattern array output scene node appearance is controlled by the pattern source."
            )
        }

        let existing: Material?
        if let assignedID = node.materialID {
            guard let assigned = productMetadata.materialLibrary.materials[assignedID] else {
                throw EditorError(
                    code: .referenceUnresolved,
                    message: "Scene node appearance requires the material the node names to exist."
                )
            }
            existing = assigned
        } else {
            existing = nil
        }

        let material = try Self.material(
            existing ?? Material.neutral(named: uniqueMaterialName(basedOn: node.name)),
            applying: edit
        )
        productMetadata.materialLibrary.materials[material.id] = material
        if existing == nil {
            productMetadata.sceneNodes[id]?.materialID = material.id
        }
        try productMetadata.validate(against: cadDocument, objectRegistry: objectRegistry)
        return material.id
    }

    /// The appearance a person can author for `id`, or `nil` when none can be.
    ///
    /// A node naming a material answers with that material. A node naming none
    /// answers with the neutral appearance, which is what the canvas already
    /// draws and what a first edit starts from, so the surface a person edits is
    /// the surface they already see. A generated pattern-array output answers
    /// with nothing, because the pattern source owns its appearance and
    /// `setSceneNodeAppearance` refuses the edit: a caller offering a control
    /// only where this answers can offer no control that fails.
    /// See `RupaCore/DESIGN.md`.
    public func authorableSceneNodeAppearance(id: SceneNodeID) -> Material? {
        guard let node = productMetadata.sceneNodes[id] else { return nil }
        guard PatternArrayOwnershipResolver().sourceID(
            containingGeneratedOutputSceneNode: id,
            in: productMetadata
        ) == nil else {
            return nil
        }
        guard let materialID = node.materialID else {
            return Material.neutral(named: node.name)
        }
        return productMetadata.materialLibrary.materials[materialID]
    }

    // MARK: - Support

    /// The material `edit` produces, validated before any document holds it.
    private static func material(
        _ material: Material,
        applying edit: MaterialComponentEdit
    ) throws -> Material {
        var edited = material
        switch edit {
        case .baseColor(let baseColor):
            edited.baseColor = baseColor
        case .opacity(let opacity):
            edited.opacity = opacity
        case .metallic(let metallic):
            edited.metallic = metallic
        case .roughness(let roughness):
            edited.roughness = roughness
        }
        do {
            try edited.validate()
        } catch let error as MaterialError {
            throw EditorError(code: .commandInvalid, message: componentDomainMessage(for: error))
        }
        return edited
    }

    private static func componentDomainMessage(for error: MaterialError) -> String {
        switch error {
        case .valueOutOfRange(let field, let value):
            return "Material \(field) must be a value from 0 to 1, not \(value)."
        }
    }

    private func materialNames() -> Set<String> {
        Set(
            productMetadata.materialLibrary.materials.values.map {
                $0.name.trimmingCharacters(in: .whitespacesAndNewlines)
            }
        )
    }

    /// The name a material created under `preferredName` carries.
    ///
    /// Two nodes may share a name and two materials may not, so a name the
    /// library already holds gains the smallest integer that separates them.
    private func uniqueMaterialName(basedOn preferredName: String) -> String {
        let trimmedName = preferredName.trimmingCharacters(in: .whitespacesAndNewlines)
        let base = trimmedName.isEmpty ? "Material" : trimmedName
        let taken = materialNames()
        guard taken.contains(base) else { return base }
        var suffix = 2
        while taken.contains("\(base) \(suffix)") {
            suffix += 1
        }
        return "\(base) \(suffix)"
    }
}
