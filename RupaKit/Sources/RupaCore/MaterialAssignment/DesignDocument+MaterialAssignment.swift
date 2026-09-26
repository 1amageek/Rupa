import Foundation
import SwiftCAD
import RupaCoreTypes

extension DesignDocument {
    /// The objects a material set on `ids` reaches: each named body, sketch or mesh object and every
    /// one inside a named group, in scene order without repeats.
    public func materialTargets(for ids: [SceneNodeID]) throws -> [SceneNodeID] {
        var targets: [SceneNodeID] = []
        var seen: Set<SceneNodeID> = []
        // Groups are searched; an object is reached and what it holds (its profile sketches and
        // carried presenters) belongs to it.
        func reach(_ nodeID: SceneNodeID) throws {
            guard seen.insert(nodeID).inserted, let node = productMetadata.sceneNodes[nodeID] else { return }
            guard carriesMaterial(node) else {
                if node.reference == nil {
                    for childID in node.childIDs { try reach(childID) }
                }
                return
            }
            guard PatternArrayOwnershipResolver().sourceID(
                containingGeneratedOutputSceneNode: nodeID, in: productMetadata
            ) == nil else {
                throw EditorError(
                    code: .commandInvalid,
                    message: "Pattern array outputs take their material from the array's source objects."
                )
            }
            targets.append(nodeID)
        }
        for id in ids {
            guard productMetadata.sceneNodes[id] != nil else {
                throw EditorError(code: .referenceUnresolved, message: "A material target does not exist.")
            }
            try reach(id)
        }
        guard !targets.isEmpty else {
            throw EditorError(code: .commandInvalid, message: "Materials apply to solids, sheets, curves and meshes.")
        }
        return targets
    }

    /// Set Material: the objects `ids` reach share one material: `materialID` from the library when
    /// given, else the one they already share or a new copy of the first one's appearance. Returns it.
    @discardableResult
    public mutating func assignMaterial(
        ids: [SceneNodeID],
        materialID: MaterialID? = nil,
        objectRegistry: ObjectTypeRegistry = .builtIn
    ) throws -> MaterialID {
        let targets = try materialTargets(for: ids)
        if let materialID {
            guard productMetadata.materialLibrary.materials[materialID] != nil else {
                throw EditorError(code: .referenceUnresolved, message: "The material to assign does not exist.")
            }
            var updated = productMetadata
            for id in targets {
                updated.sceneNodes[id]?.materialID = materialID
            }
            try updated.validate(against: cadDocument, objectRegistry: objectRegistry)
            productMetadata = updated
            return materialID
        }
        let assigned = Set(targets.map { productMetadata.sceneNodes[$0]?.materialID })
        if assigned.count == 1, let shared = assigned.first ?? nil, productMetadata.materialLibrary.materials[shared] != nil {
            return shared
        }
        return try forkMaterial(ids: ids, objectRegistry: objectRegistry)
    }

    /// Fork Material: the objects `ids` reach take a new copy of the first one's appearance.
    @discardableResult
    public mutating func forkMaterial(ids: [SceneNodeID], objectRegistry: ObjectTypeRegistry = .builtIn) throws -> MaterialID {
        let targets = try materialTargets(for: ids)
        guard let first = productMetadata.sceneNodes[targets[0]] else {
            throw EditorError(code: .referenceUnresolved, message: "A material target does not exist.")
        }
        let material = Self.copy(appearance(of: first), named: uniqueMaterialName(basedOn: first.name))
        var updated = productMetadata
        updated.materialLibrary.materials[material.id] = material
        for id in targets {
            updated.sceneNodes[id]?.materialID = material.id
        }
        try updated.validate(against: cadDocument, objectRegistry: objectRegistry)
        productMetadata = updated
        return material.id
    }

    /// Remove Material: the objects `ids` reach and their faces return to the document default.
    public mutating func removeMaterial(ids: [SceneNodeID], objectRegistry: ObjectTypeRegistry = .builtIn) throws {
        let targets = Set(try materialTargets(for: ids))
        var updated = productMetadata
        for id in targets {
            updated.sceneNodes[id]?.materialID = nil
        }
        updated.topologyMaterialBindings = updated.topologyMaterialBindings.filter { !targets.contains($0.value.target.sceneNodeID) }
        try updated.validate(against: cadDocument, objectRegistry: objectRegistry)
        productMetadata = updated
    }

    /// Changes one component of a library material; every object and face naming it follows.
    public mutating func editMaterial(
        id: MaterialID,
        edit: MaterialComponentEdit,
        objectRegistry: ObjectTypeRegistry = .builtIn
    ) throws {
        guard let material = productMetadata.materialLibrary.materials[id] else {
            throw EditorError(code: .referenceUnresolved, message: "The material to edit does not exist.")
        }
        var updated = productMetadata
        updated.materialLibrary.materials[id] = try Self.material(material, applying: edit)
        try updated.validate(against: cadDocument, objectRegistry: objectRegistry)
        productMetadata = updated
    }

    /// Adds a neutral material named `name` (made unique) to the library.
    @discardableResult
    public mutating func createMaterial(name: String, objectRegistry: ObjectTypeRegistry = .builtIn) throws -> MaterialID {
        let material = Material.neutral(named: uniqueMaterialName(basedOn: name))
        var updated = productMetadata
        updated.materialLibrary.materials[material.id] = material
        try updated.validate(against: cadDocument, objectRegistry: objectRegistry)
        productMetadata = updated
        return material.id
    }

    /// Renames a library material; another material already holding the name is a refusal.
    public mutating func renameMaterial(id: MaterialID, name: String, objectRegistry: ObjectTypeRegistry = .builtIn) throws {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw EditorError(code: .commandInvalid, message: "A material needs a name.")
        }
        guard productMetadata.materialLibrary.materials[id] != nil else {
            throw EditorError(code: .referenceUnresolved, message: "The material to rename does not exist.")
        }
        guard !productMetadata.materialLibrary.materials.values.contains(where: {
            $0.id != id && $0.name.trimmingCharacters(in: .whitespacesAndNewlines) == trimmed
        }) else {
            throw EditorError(code: .commandInvalid, message: "Another material is already named \(trimmed).")
        }
        var updated = productMetadata
        updated.materialLibrary.materials[id]?.name = trimmed
        try updated.validate(against: cadDocument, objectRegistry: objectRegistry)
        productMetadata = updated
    }

    /// Deletes a library material; the objects and faces naming it return to the document default.
    public mutating func deleteMaterial(id: MaterialID, objectRegistry: ObjectTypeRegistry = .builtIn) throws {
        guard productMetadata.materialLibrary.materials[id] != nil else {
            throw EditorError(code: .referenceUnresolved, message: "The material to delete does not exist.")
        }
        var updated = productMetadata
        updated.materialLibrary.materials.removeValue(forKey: id)
        if updated.materialLibrary.defaultMaterialID == id {
            updated.materialLibrary.defaultMaterialID = nil
        }
        for (nodeID, node) in updated.sceneNodes where node.materialID == id {
            updated.sceneNodes[nodeID]?.materialID = nil
        }
        updated.topologyMaterialBindings = updated.topologyMaterialBindings.filter { $0.value.materialID != id }
        try updated.validate(against: cadDocument, objectRegistry: objectRegistry)
        productMetadata = updated
    }

    /// The mass of `measurement`'s solids from the densities of the materials their objects carry.
    public func mass(of measurement: MeasurementResult) throws -> SceneMass {
        let hierarchy = try SceneNodeHierarchy(metadata: productMetadata)
        var kilograms = 0.0
        var unweighed = 0
        for solid in measurement.solids {
            guard let uuid = UUID(uuidString: solid.featureID),
                  let featureID = Optional(FeatureID(uuid)),
                  let nodeID = hierarchy.presentingSceneNodeID(for: featureID),
                  let node = productMetadata.sceneNodes[nodeID],
                  let density = appearance(of: node).density else {
                unweighed += 1
                continue
            }
            kilograms += solid.volumeCubicMeters * density
        }
        return SceneMass(kilograms: kilograms, unweighedSolidCount: unweighed)
    }

    private func carriesMaterial(_ node: SceneNode) -> Bool {
        switch node.reference?.kind {
        case .body, .feature, .sketch, .authoredMesh: true
        case .componentInstance, .construction, nil: false
        }
    }
}

/// The mass of measured solids and how many had no density to weigh them by.
public struct SceneMass: Equatable, Sendable {
    public var kilograms: Double
    public var unweighedSolidCount: Int

    public init(kilograms: Double, unweighedSolidCount: Int) {
        self.kilograms = kilograms
        self.unweighedSolidCount = unweighedSolidCount
    }
}
