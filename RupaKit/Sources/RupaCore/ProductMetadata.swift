import Foundation
import SwiftCAD

public struct ProductMetadata: Codable, Hashable, Sendable {
    public var sceneNodes: [SceneNodeID: SceneNode]
    public var rootSceneNodeIDs: [SceneNodeID]
    public var componentDefinitions: [ComponentDefinitionID: ComponentDefinition]
    public var componentInstances: [ComponentInstanceID: ComponentInstance]
    public var materialLibrary: MaterialLibrary
    public var validationRules: [ValidationRuleID: ValidationRule]
    public var exportPresets: [ExportPresetID: ExportPreset]
    public var templateDefaults: TemplateDefaults

    public init(
        sceneNodes: [SceneNodeID: SceneNode],
        rootSceneNodeIDs: [SceneNodeID],
        componentDefinitions: [ComponentDefinitionID: ComponentDefinition] = [:],
        componentInstances: [ComponentInstanceID: ComponentInstance] = [:],
        materialLibrary: MaterialLibrary = MaterialLibrary(),
        validationRules: [ValidationRuleID: ValidationRule] = [:],
        exportPresets: [ExportPresetID: ExportPreset] = [:],
        templateDefaults: TemplateDefaults = TemplateDefaults()
    ) {
        self.sceneNodes = sceneNodes
        self.rootSceneNodeIDs = rootSceneNodeIDs
        self.componentDefinitions = componentDefinitions
        self.componentInstances = componentInstances
        self.materialLibrary = materialLibrary
        self.validationRules = validationRules
        self.exportPresets = exportPresets
        self.templateDefaults = templateDefaults
    }

    public static func empty() -> ProductMetadata {
        let root = SceneNode(name: "Scene")
        return ProductMetadata(
            sceneNodes: [root.id: root],
            rootSceneNodeIDs: [root.id]
        )
    }

    public func validate(
        against cadDocument: CADDocument,
        objectRegistry: ObjectTypeRegistry
    ) throws {
        try validateSceneNodes(against: cadDocument, objectRegistry: objectRegistry)
        try validateComponentDefinitions()
        try validateComponentInstances()
        try materialLibrary.validate()
        try validateValidationRules()
        try validateExportPresets()
        try validateTemplateDefaults()
    }

    public mutating func appendSceneNodeToFirstRoot(
        name: String,
        reference: SceneNodeReference,
        object: ObjectDescriptor? = nil
    ) throws -> SceneNodeID {
        guard let rootSceneNodeID = rootSceneNodeIDs.first else {
            throw DocumentValidationError.invalidProductMetadata("A document must contain at least one root scene node.")
        }
        guard sceneNodes[rootSceneNodeID] != nil else {
            throw DocumentValidationError.invalidProductMetadata("Root scene node references a missing node.")
        }

        let sceneNode = SceneNode(
            name: name,
            reference: reference,
            object: object
        )
        sceneNodes[sceneNode.id] = sceneNode
        sceneNodes[rootSceneNodeID]?.childIDs.append(sceneNode.id)
        return sceneNode.id
    }

    private func validateSceneNodes(
        against cadDocument: CADDocument,
        objectRegistry: ObjectTypeRegistry
    ) throws {
        guard !rootSceneNodeIDs.isEmpty else {
            throw DocumentValidationError.invalidProductMetadata("A document must contain at least one root scene node.")
        }
        guard Set(rootSceneNodeIDs).count == rootSceneNodeIDs.count else {
            throw DocumentValidationError.invalidProductMetadata("Root scene node references must be unique.")
        }

        for rootSceneNodeID in rootSceneNodeIDs {
            guard sceneNodes[rootSceneNodeID] != nil else {
                throw DocumentValidationError.invalidProductMetadata("Root scene node references a missing node.")
            }
        }

        for (sceneNodeID, sceneNode) in sceneNodes {
            guard sceneNode.id == sceneNodeID else {
                throw DocumentValidationError.invalidProductMetadata("Scene node keys must match scene node IDs.")
            }
            try sceneNode.validate()
            if let materialID = sceneNode.materialID,
               materialLibrary.materials[materialID] == nil {
                throw DocumentValidationError.invalidProductMetadata(
                    "Scene node material references a missing material."
                )
            }
            for childID in sceneNode.childIDs {
                guard sceneNodes[childID] != nil else {
                    throw DocumentValidationError.invalidProductMetadata("Scene node child references a missing node.")
                }
            }
            try validateSceneReference(sceneNode.reference, against: cadDocument)
            try validateObjectDescriptor(
                sceneNode.object,
                reference: sceneNode.reference,
                against: cadDocument,
                objectRegistry: objectRegistry
            )
        }

        try validateSceneHierarchy()
    }

    private func validateSceneReference(
        _ reference: SceneNodeReference?,
        against cadDocument: CADDocument
    ) throws {
        guard let reference else {
            return
        }
        switch reference.kind {
        case .feature:
            guard let featureID = reference.featureID,
                  cadDocument.designGraph.nodes[featureID] != nil else {
                throw DocumentValidationError.invalidProductMetadata(
                    "Scene node feature references must point to an existing CAD feature."
                )
            }
        case .body:
            guard let featureID = reference.featureID,
                  let feature = cadDocument.designGraph.nodes[featureID],
                  feature.outputs.contains(where: { $0.role == .body }) else {
                throw DocumentValidationError.invalidProductMetadata(
                    "Scene node body references must point to an existing CAD body-producing feature."
                )
            }
        case .sketch:
            guard let featureID = reference.featureID,
                  let feature = cadDocument.designGraph.nodes[featureID],
                  feature.outputs.contains(where: { $0.role == .profile }) else {
                throw DocumentValidationError.invalidProductMetadata(
                    "Scene node sketch references must point to an existing CAD sketch profile feature."
                )
            }
        case .componentInstance:
            guard let componentInstanceID = reference.componentInstanceID,
                  componentInstances[componentInstanceID] != nil else {
                throw DocumentValidationError.invalidProductMetadata(
                    "Scene node component references must point to an existing component instance."
                )
            }
        case .construction:
            return
        }
    }

    private func validateObjectDescriptor(
        _ object: ObjectDescriptor?,
        reference: SceneNodeReference?,
        against cadDocument: CADDocument,
        objectRegistry: ObjectTypeRegistry
    ) throws {
        guard let object else {
            return
        }
        try object.validate()
        let definition = try object.typeID.map { typeID in
            try objectRegistry.requireDefinition(for: typeID)
        }
        if let definition {
            guard object.category == definition.category else {
                throw DocumentValidationError.invalidProductMetadata(
                    "Object category must match object type \(definition.id.rawValue)."
                )
            }
            if let geometryRole = definition.geometryRole {
                guard object.geometryRole == geometryRole else {
                    throw DocumentValidationError.invalidProductMetadata(
                        "Object geometry role must match object type \(definition.id.rawValue)."
                    )
                }
            }
        }
        switch object.category {
        case .group:
            guard reference == nil else {
                throw DocumentValidationError.invalidProductMetadata(
                    "Group objects must not point to CAD source references."
                )
            }
        case .body:
            guard reference?.kind == .body,
                  reference?.featureID == object.sourceFeatureID,
                  let sourceFeatureID = object.sourceFeatureID,
                  let feature = cadDocument.designGraph.nodes[sourceFeatureID],
                  feature.outputs.contains(where: { $0.role == .body }) else {
                throw DocumentValidationError.invalidProductMetadata(
                    "Body objects must point to a body-producing CAD feature."
                )
            }
            if let sourceProfileFeatureID = object.sourceProfileFeatureID {
                guard let profileFeature = cadDocument.designGraph.nodes[sourceProfileFeatureID],
                      profileFeature.outputs.contains(where: { $0.role == .profile }) else {
                    throw DocumentValidationError.invalidProductMetadata(
                        "Body object source profiles must point to CAD sketch profile features."
                    )
                }
            }
        case .sketch:
            guard reference?.kind == .sketch,
                  reference?.featureID == object.sourceFeatureID,
                  let sourceFeatureID = object.sourceFeatureID,
                  let feature = cadDocument.designGraph.nodes[sourceFeatureID],
                  feature.outputs.contains(where: { $0.role == .profile }) else {
                throw DocumentValidationError.invalidProductMetadata(
                    "Sketch objects must point to a CAD sketch profile or curve feature."
                )
            }
        case .componentInstance:
            guard reference?.kind == .componentInstance,
                  reference?.componentInstanceID == object.componentInstanceID,
                  let componentInstanceID = object.componentInstanceID,
                  componentInstances[componentInstanceID] != nil else {
                throw DocumentValidationError.invalidProductMetadata(
                    "Component instance objects must point to an existing component instance."
                )
            }
        case .construction:
            guard reference?.kind == .construction else {
                throw DocumentValidationError.invalidProductMetadata(
                    "Construction objects must use construction scene references."
                )
            }
        case .annotation:
            break
        case .camera, .light:
            return
        }
        if let definition {
            try object.properties.validate(
                against: definition,
                materialLibrary: materialLibrary
            )
        }
    }

    private func validateSceneHierarchy() throws {
        var visited: Set<SceneNodeID> = []
        var visiting: Set<SceneNodeID> = []
        var parentByChild: [SceneNodeID: SceneNodeID] = [:]

        for rootSceneNodeID in rootSceneNodeIDs {
            try visitSceneNode(
                rootSceneNodeID,
                visited: &visited,
                visiting: &visiting,
                parentByChild: &parentByChild
            )
        }

        guard visited == Set(sceneNodes.keys) else {
            throw DocumentValidationError.invalidProductMetadata(
                "Every scene node must be reachable from the root scene nodes."
            )
        }
    }

    private func visitSceneNode(
        _ sceneNodeID: SceneNodeID,
        visited: inout Set<SceneNodeID>,
        visiting: inout Set<SceneNodeID>,
        parentByChild: inout [SceneNodeID: SceneNodeID]
    ) throws {
        guard !visiting.contains(sceneNodeID) else {
            throw DocumentValidationError.invalidProductMetadata("Scene node hierarchy must not contain cycles.")
        }
        guard !visited.contains(sceneNodeID) else {
            return
        }
        guard let sceneNode = sceneNodes[sceneNodeID] else {
            throw DocumentValidationError.invalidProductMetadata("Scene node hierarchy references a missing node.")
        }

        visiting.insert(sceneNodeID)
        for childID in sceneNode.childIDs {
            if let existingParentID = parentByChild[childID], existingParentID != sceneNodeID {
                throw DocumentValidationError.invalidProductMetadata(
                    "Scene nodes must not have multiple parents."
                )
            }
            parentByChild[childID] = sceneNodeID
            try visitSceneNode(
                childID,
                visited: &visited,
                visiting: &visiting,
                parentByChild: &parentByChild
            )
        }
        visiting.remove(sceneNodeID)
        visited.insert(sceneNodeID)
    }

    private func validateComponentDefinitions() throws {
        var names: Set<String> = []
        for (definitionID, definition) in componentDefinitions {
            guard definition.id == definitionID else {
                throw DocumentValidationError.invalidProductMetadata(
                    "Component definition keys must match definition IDs."
                )
            }
            let trimmedName = definition.name.trimmingCharacters(in: .whitespacesAndNewlines)
            guard names.insert(trimmedName).inserted else {
                throw DocumentValidationError.invalidProductMetadata(
                    "Component definition names must be unique."
                )
            }
            try definition.validate()
            for rootSceneNodeID in definition.rootSceneNodeIDs {
                guard sceneNodes[rootSceneNodeID] != nil else {
                    throw DocumentValidationError.invalidProductMetadata(
                        "Component definition root scene node references a missing node."
                    )
                }
            }
        }
    }

    private func validateComponentInstances() throws {
        var names: Set<String> = []
        for (instanceID, instance) in componentInstances {
            guard instance.id == instanceID else {
                throw DocumentValidationError.invalidProductMetadata(
                    "Component instance keys must match instance IDs."
                )
            }
            guard componentDefinitions[instance.definitionID] != nil else {
                throw DocumentValidationError.invalidProductMetadata(
                    "Component instances must reference existing component definitions."
                )
            }
            let trimmedName = instance.name.trimmingCharacters(in: .whitespacesAndNewlines)
            guard names.insert(trimmedName).inserted else {
                throw DocumentValidationError.invalidProductMetadata("Component instance names must be unique.")
            }
            try instance.validate()
        }
    }

    private func validateValidationRules() throws {
        var names: Set<String> = []
        for (ruleID, rule) in validationRules {
            guard rule.id == ruleID else {
                throw DocumentValidationError.invalidProductMetadata("Validation rule keys must match rule IDs.")
            }
            let trimmedName = rule.name.trimmingCharacters(in: .whitespacesAndNewlines)
            guard names.insert(trimmedName).inserted else {
                throw DocumentValidationError.invalidProductMetadata("Validation rule names must be unique.")
            }
            try rule.validate()
        }
    }

    private func validateExportPresets() throws {
        var names: Set<String> = []
        for (presetID, preset) in exportPresets {
            guard preset.id == presetID else {
                throw DocumentValidationError.invalidProductMetadata("Export preset keys must match preset IDs.")
            }
            let trimmedName = preset.name.trimmingCharacters(in: .whitespacesAndNewlines)
            guard names.insert(trimmedName).inserted else {
                throw DocumentValidationError.invalidProductMetadata("Export preset names must be unique.")
            }
            try preset.validate()
            for ruleID in preset.validationRuleIDs {
                guard validationRules[ruleID] != nil else {
                    throw DocumentValidationError.invalidProductMetadata(
                        "Export presets must reference existing validation rules."
                    )
                }
            }
        }
    }

    private func validateTemplateDefaults() throws {
        try templateDefaults.validate()
        if let defaultMaterialID = templateDefaults.defaultMaterialID {
            guard materialLibrary.materials[defaultMaterialID] != nil else {
                throw DocumentValidationError.invalidProductMetadata(
                    "Template default material must exist in the material library."
                )
            }
        }
        for ruleID in templateDefaults.validationRuleIDs {
            guard validationRules[ruleID] != nil else {
                throw DocumentValidationError.invalidProductMetadata(
                    "Template defaults must reference existing validation rules."
                )
            }
        }
        for presetID in templateDefaults.exportPresetIDs {
            guard exportPresets[presetID] != nil else {
                throw DocumentValidationError.invalidProductMetadata(
                    "Template defaults must reference existing export presets."
                )
            }
        }
    }
}
