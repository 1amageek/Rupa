import Foundation
import SwiftCAD

public struct RupaProductMetadata: Codable, Hashable, Sendable {
    public var sceneNodes: [RupaSceneNodeID: RupaSceneNode]
    public var rootSceneNodeIDs: [RupaSceneNodeID]
    public var componentDefinitions: [RupaComponentDefinitionID: RupaComponentDefinition]
    public var componentInstances: [RupaComponentInstanceID: RupaComponentInstance]
    public var materialLibrary: RupaMaterialLibrary
    public var validationRules: [RupaValidationRuleID: RupaValidationRule]
    public var exportPresets: [RupaExportPresetID: RupaExportPreset]
    public var templateDefaults: RupaTemplateDefaults

    public init(
        sceneNodes: [RupaSceneNodeID: RupaSceneNode],
        rootSceneNodeIDs: [RupaSceneNodeID],
        componentDefinitions: [RupaComponentDefinitionID: RupaComponentDefinition] = [:],
        componentInstances: [RupaComponentInstanceID: RupaComponentInstance] = [:],
        materialLibrary: RupaMaterialLibrary = RupaMaterialLibrary(),
        validationRules: [RupaValidationRuleID: RupaValidationRule] = [:],
        exportPresets: [RupaExportPresetID: RupaExportPreset] = [:],
        templateDefaults: RupaTemplateDefaults = RupaTemplateDefaults()
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

    public static func empty() -> RupaProductMetadata {
        let root = RupaSceneNode(name: "Scene")
        return RupaProductMetadata(
            sceneNodes: [root.id: root],
            rootSceneNodeIDs: [root.id]
        )
    }

    public func validate(against cadDocument: CADDocument) throws {
        try validateSceneNodes(against: cadDocument)
        try validateComponentDefinitions()
        try validateComponentInstances()
        try materialLibrary.validate()
        try validateValidationRules()
        try validateExportPresets()
        try validateTemplateDefaults()
    }

    public mutating func appendSceneNodeToFirstRoot(
        name: String,
        reference: RupaSceneNodeReference
    ) throws -> RupaSceneNodeID {
        guard let rootSceneNodeID = rootSceneNodeIDs.first else {
            throw RupaDocumentValidationError.invalidProductMetadata("A document must contain at least one root scene node.")
        }
        guard sceneNodes[rootSceneNodeID] != nil else {
            throw RupaDocumentValidationError.invalidProductMetadata("Root scene node references a missing node.")
        }

        let sceneNode = RupaSceneNode(
            name: name,
            reference: reference
        )
        sceneNodes[sceneNode.id] = sceneNode
        sceneNodes[rootSceneNodeID]?.childIDs.append(sceneNode.id)
        return sceneNode.id
    }

    private func validateSceneNodes(against cadDocument: CADDocument) throws {
        guard !rootSceneNodeIDs.isEmpty else {
            throw RupaDocumentValidationError.invalidProductMetadata("A document must contain at least one root scene node.")
        }
        guard Set(rootSceneNodeIDs).count == rootSceneNodeIDs.count else {
            throw RupaDocumentValidationError.invalidProductMetadata("Root scene node references must be unique.")
        }

        for rootSceneNodeID in rootSceneNodeIDs {
            guard sceneNodes[rootSceneNodeID] != nil else {
                throw RupaDocumentValidationError.invalidProductMetadata("Root scene node references a missing node.")
            }
        }

        for (sceneNodeID, sceneNode) in sceneNodes {
            guard sceneNode.id == sceneNodeID else {
                throw RupaDocumentValidationError.invalidProductMetadata("Scene node keys must match scene node IDs.")
            }
            try sceneNode.validate()
            if let materialID = sceneNode.materialID,
               materialLibrary.materials[materialID] == nil {
                throw RupaDocumentValidationError.invalidProductMetadata(
                    "Scene node material references a missing material."
                )
            }
            for childID in sceneNode.childIDs {
                guard sceneNodes[childID] != nil else {
                    throw RupaDocumentValidationError.invalidProductMetadata("Scene node child references a missing node.")
                }
            }
            try validateSceneReference(sceneNode.reference, against: cadDocument)
        }

        try validateSceneHierarchy()
    }

    private func validateSceneReference(
        _ reference: RupaSceneNodeReference?,
        against cadDocument: CADDocument
    ) throws {
        guard let reference else {
            return
        }
        switch reference.kind {
        case .feature:
            guard let featureID = reference.featureID,
                  cadDocument.designGraph.nodes[featureID] != nil else {
                throw RupaDocumentValidationError.invalidProductMetadata(
                    "Scene node feature references must point to an existing CAD feature."
                )
            }
        case .body:
            guard let featureID = reference.featureID,
                  let feature = cadDocument.designGraph.nodes[featureID],
                  feature.outputs.contains(where: { $0.role == .body }) else {
                throw RupaDocumentValidationError.invalidProductMetadata(
                    "Scene node body references must point to an existing CAD body-producing feature."
                )
            }
        case .sketch:
            guard let featureID = reference.featureID,
                  let feature = cadDocument.designGraph.nodes[featureID],
                  feature.outputs.contains(where: { $0.role == .profile }) else {
                throw RupaDocumentValidationError.invalidProductMetadata(
                    "Scene node sketch references must point to an existing CAD sketch profile feature."
                )
            }
        case .componentInstance:
            guard let componentInstanceID = reference.componentInstanceID,
                  componentInstances[componentInstanceID] != nil else {
                throw RupaDocumentValidationError.invalidProductMetadata(
                    "Scene node component references must point to an existing component instance."
                )
            }
        case .construction:
            return
        }
    }

    private func validateSceneHierarchy() throws {
        var visited: Set<RupaSceneNodeID> = []
        var visiting: Set<RupaSceneNodeID> = []
        var parentByChild: [RupaSceneNodeID: RupaSceneNodeID] = [:]

        for rootSceneNodeID in rootSceneNodeIDs {
            try visitSceneNode(
                rootSceneNodeID,
                visited: &visited,
                visiting: &visiting,
                parentByChild: &parentByChild
            )
        }

        guard visited == Set(sceneNodes.keys) else {
            throw RupaDocumentValidationError.invalidProductMetadata(
                "Every scene node must be reachable from the root scene nodes."
            )
        }
    }

    private func visitSceneNode(
        _ sceneNodeID: RupaSceneNodeID,
        visited: inout Set<RupaSceneNodeID>,
        visiting: inout Set<RupaSceneNodeID>,
        parentByChild: inout [RupaSceneNodeID: RupaSceneNodeID]
    ) throws {
        guard !visiting.contains(sceneNodeID) else {
            throw RupaDocumentValidationError.invalidProductMetadata("Scene node hierarchy must not contain cycles.")
        }
        guard !visited.contains(sceneNodeID) else {
            return
        }
        guard let sceneNode = sceneNodes[sceneNodeID] else {
            throw RupaDocumentValidationError.invalidProductMetadata("Scene node hierarchy references a missing node.")
        }

        visiting.insert(sceneNodeID)
        for childID in sceneNode.childIDs {
            if let existingParentID = parentByChild[childID], existingParentID != sceneNodeID {
                throw RupaDocumentValidationError.invalidProductMetadata(
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
                throw RupaDocumentValidationError.invalidProductMetadata(
                    "Component definition keys must match definition IDs."
                )
            }
            let trimmedName = definition.name.trimmingCharacters(in: .whitespacesAndNewlines)
            guard names.insert(trimmedName).inserted else {
                throw RupaDocumentValidationError.invalidProductMetadata(
                    "Component definition names must be unique."
                )
            }
            try definition.validate()
            for rootSceneNodeID in definition.rootSceneNodeIDs {
                guard sceneNodes[rootSceneNodeID] != nil else {
                    throw RupaDocumentValidationError.invalidProductMetadata(
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
                throw RupaDocumentValidationError.invalidProductMetadata(
                    "Component instance keys must match instance IDs."
                )
            }
            guard componentDefinitions[instance.definitionID] != nil else {
                throw RupaDocumentValidationError.invalidProductMetadata(
                    "Component instances must reference existing component definitions."
                )
            }
            let trimmedName = instance.name.trimmingCharacters(in: .whitespacesAndNewlines)
            guard names.insert(trimmedName).inserted else {
                throw RupaDocumentValidationError.invalidProductMetadata("Component instance names must be unique.")
            }
            try instance.validate()
        }
    }

    private func validateValidationRules() throws {
        var names: Set<String> = []
        for (ruleID, rule) in validationRules {
            guard rule.id == ruleID else {
                throw RupaDocumentValidationError.invalidProductMetadata("Validation rule keys must match rule IDs.")
            }
            let trimmedName = rule.name.trimmingCharacters(in: .whitespacesAndNewlines)
            guard names.insert(trimmedName).inserted else {
                throw RupaDocumentValidationError.invalidProductMetadata("Validation rule names must be unique.")
            }
            try rule.validate()
        }
    }

    private func validateExportPresets() throws {
        var names: Set<String> = []
        for (presetID, preset) in exportPresets {
            guard preset.id == presetID else {
                throw RupaDocumentValidationError.invalidProductMetadata("Export preset keys must match preset IDs.")
            }
            let trimmedName = preset.name.trimmingCharacters(in: .whitespacesAndNewlines)
            guard names.insert(trimmedName).inserted else {
                throw RupaDocumentValidationError.invalidProductMetadata("Export preset names must be unique.")
            }
            try preset.validate()
            for ruleID in preset.validationRuleIDs {
                guard validationRules[ruleID] != nil else {
                    throw RupaDocumentValidationError.invalidProductMetadata(
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
                throw RupaDocumentValidationError.invalidProductMetadata(
                    "Template default material must exist in the material library."
                )
            }
        }
        for ruleID in templateDefaults.validationRuleIDs {
            guard validationRules[ruleID] != nil else {
                throw RupaDocumentValidationError.invalidProductMetadata(
                    "Template defaults must reference existing validation rules."
                )
            }
        }
        for presetID in templateDefaults.exportPresetIDs {
            guard exportPresets[presetID] != nil else {
                throw RupaDocumentValidationError.invalidProductMetadata(
                    "Template defaults must reference existing export presets."
                )
            }
        }
    }
}
