import Foundation
import SwiftCAD

public struct CommandGeneratedIdentityDelta: Codable, Equatable, Sendable {
    public let featureIDs: [FeatureID]
    public let sourceBodyOutputs: [GeneratedSourceBodyOutputIdentity]
    public let sceneNodeIDs: [SceneNodeID]
    public let componentDefinitionIDs: [ComponentDefinitionID]
    public let componentInstanceIDs: [ComponentInstanceID]
    public let patternArraySourceIDs: [PatternArraySourceID]

    public static let empty = CommandGeneratedIdentityDelta(
        featureIDs: [],
        sourceBodyOutputs: [],
        sceneNodeIDs: [],
        componentDefinitionIDs: [],
        componentInstanceIDs: [],
        patternArraySourceIDs: []
    )

    public var isEmpty: Bool {
        featureIDs.isEmpty
            && sourceBodyOutputs.isEmpty
            && sceneNodeIDs.isEmpty
            && componentDefinitionIDs.isEmpty
            && componentInstanceIDs.isEmpty
            && patternArraySourceIDs.isEmpty
    }

    private init(
        featureIDs: [FeatureID],
        sourceBodyOutputs: [GeneratedSourceBodyOutputIdentity],
        sceneNodeIDs: [SceneNodeID],
        componentDefinitionIDs: [ComponentDefinitionID],
        componentInstanceIDs: [ComponentInstanceID],
        patternArraySourceIDs: [PatternArraySourceID]
    ) {
        self.featureIDs = featureIDs
        self.sourceBodyOutputs = sourceBodyOutputs
        self.sceneNodeIDs = sceneNodeIDs
        self.componentDefinitionIDs = componentDefinitionIDs
        self.componentInstanceIDs = componentInstanceIDs
        self.patternArraySourceIDs = patternArraySourceIDs
    }

    init(
        before: DesignDocument,
        after: DesignDocument,
        didMutate: Bool
    ) throws {
        let beforeFeatureIDs = Set(before.cadDocument.designGraph.nodes.keys)
        let beforeSceneNodeIDs = Set(before.productMetadata.sceneNodes.keys)
        let beforeComponentDefinitionIDs = Set(before.productMetadata.componentDefinitions.keys)
        let beforeComponentInstanceIDs = Set(before.productMetadata.componentInstances.keys)
        let beforePatternArraySourceIDs = Set(before.productMetadata.patternArrays.keys)

        let afterFeatureIDs = Set(after.cadDocument.designGraph.nodes.keys)
        let afterSceneNodeIDs = Set(after.productMetadata.sceneNodes.keys)
        let afterComponentDefinitionIDs = Set(after.productMetadata.componentDefinitions.keys)
        let afterComponentInstanceIDs = Set(after.productMetadata.componentInstances.keys)
        let afterPatternArraySourceIDs = Set(after.productMetadata.patternArrays.keys)

        if !didMutate,
           beforeFeatureIDs != afterFeatureIDs
            || beforeSceneNodeIDs != afterSceneNodeIDs
            || beforeComponentDefinitionIDs != afterComponentDefinitionIDs
            || beforeComponentInstanceIDs != afterComponentInstanceIDs
            || beforePatternArraySourceIDs != afterPatternArraySourceIDs {
            throw CommandGeneratedIdentityError.identityChangedWithoutMutation
        }

        let featureIDs = try Self.generatedFeatureIDs(
            beforeIDs: beforeFeatureIDs,
            after: after
        )
        let sourceBodyOutputs = try Self.generatedBodyOutputs(
            featureIDs: featureIDs,
            after: after
        )
        let sceneNodeIDs = try Self.generatedSceneNodeIDs(
            beforeIDs: beforeSceneNodeIDs,
            after: after
        )
        let componentDefinitionIDs = try Self.generatedComponentDefinitionIDs(
            beforeIDs: beforeComponentDefinitionIDs,
            after: after
        )
        let componentInstanceIDs = try Self.generatedComponentInstanceIDs(
            beforeIDs: beforeComponentInstanceIDs,
            after: after
        )
        let patternArraySourceIDs = try Self.generatedPatternArraySourceIDs(
            beforeIDs: beforePatternArraySourceIDs,
            after: after
        )
        try Self.validateStructure(
            featureIDs: featureIDs,
            sourceBodyOutputs: sourceBodyOutputs,
            sceneNodeIDs: sceneNodeIDs,
            componentDefinitionIDs: componentDefinitionIDs,
            componentInstanceIDs: componentInstanceIDs,
            patternArraySourceIDs: patternArraySourceIDs
        )
        self.init(
            featureIDs: featureIDs,
            sourceBodyOutputs: sourceBodyOutputs,
            sceneNodeIDs: sceneNodeIDs,
            componentDefinitionIDs: componentDefinitionIDs,
            componentInstanceIDs: componentInstanceIDs,
            patternArraySourceIDs: patternArraySourceIDs
        )
    }

    private enum CodingKeys: String, CodingKey {
        case featureIDs
        case sourceBodyOutputs
        case sceneNodeIDs
        case componentDefinitionIDs
        case componentInstanceIDs
        case patternArraySourceIDs
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try container.validateOnlyExpectedKeys([
            .featureIDs,
            .sourceBodyOutputs,
            .sceneNodeIDs,
            .componentDefinitionIDs,
            .componentInstanceIDs,
            .patternArraySourceIDs,
        ], in: decoder)
        let featureIDs = try container.decode([FeatureID].self, forKey: .featureIDs)
        let sourceBodyOutputs = try container.decode(
            [GeneratedSourceBodyOutputIdentity].self,
            forKey: .sourceBodyOutputs
        )
        let sceneNodeIDs = try container.decode([SceneNodeID].self, forKey: .sceneNodeIDs)
        let componentDefinitionIDs = try container.decode(
            [ComponentDefinitionID].self,
            forKey: .componentDefinitionIDs
        )
        let componentInstanceIDs = try container.decode(
            [ComponentInstanceID].self,
            forKey: .componentInstanceIDs
        )
        let patternArraySourceIDs = try container.decode(
            [PatternArraySourceID].self,
            forKey: .patternArraySourceIDs
        )
        try Self.validateStructure(
            featureIDs: featureIDs,
            sourceBodyOutputs: sourceBodyOutputs,
            sceneNodeIDs: sceneNodeIDs,
            componentDefinitionIDs: componentDefinitionIDs,
            componentInstanceIDs: componentInstanceIDs,
            patternArraySourceIDs: patternArraySourceIDs
        )
        self.init(
            featureIDs: featureIDs,
            sourceBodyOutputs: sourceBodyOutputs,
            sceneNodeIDs: sceneNodeIDs,
            componentDefinitionIDs: componentDefinitionIDs,
            componentInstanceIDs: componentInstanceIDs,
            patternArraySourceIDs: patternArraySourceIDs
        )
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(featureIDs, forKey: .featureIDs)
        try container.encode(sourceBodyOutputs, forKey: .sourceBodyOutputs)
        try container.encode(sceneNodeIDs, forKey: .sceneNodeIDs)
        try container.encode(componentDefinitionIDs, forKey: .componentDefinitionIDs)
        try container.encode(componentInstanceIDs, forKey: .componentInstanceIDs)
        try container.encode(patternArraySourceIDs, forKey: .patternArraySourceIDs)
    }

    private static func validateStructure(
        featureIDs: [FeatureID],
        sourceBodyOutputs: [GeneratedSourceBodyOutputIdentity],
        sceneNodeIDs: [SceneNodeID],
        componentDefinitionIDs: [ComponentDefinitionID],
        componentInstanceIDs: [ComponentInstanceID],
        patternArraySourceIDs: [PatternArraySourceID]
    ) throws {
        if let duplicate = firstDuplicate(in: featureIDs) {
            throw CommandGeneratedIdentityError.duplicateFeatureIdentity(duplicate)
        }
        let featureIDSet = Set(featureIDs)
        var bodyRoleByFeatureID: [FeatureID: SourceBodyOutputRole] = [:]
        for output in sourceBodyOutputs {
            guard featureIDSet.contains(output.featureID) else {
                throw CommandGeneratedIdentityError.bodyOutputWithoutGeneratedFeature(
                    output.featureID
                )
            }
            if let existingRole = bodyRoleByFeatureID[output.featureID] {
                if existingRole == output.role {
                    throw CommandGeneratedIdentityError.duplicateBodyOutput(
                        output.featureID,
                        output.role
                    )
                }
                throw CommandGeneratedIdentityError.ambiguousBodyOutput(output.featureID)
            }
            bodyRoleByFeatureID[output.featureID] = output.role
        }
        if let duplicate = firstDuplicate(in: sceneNodeIDs) {
            throw CommandGeneratedIdentityError.duplicateSceneIdentity(duplicate)
        }
        if let duplicate = firstDuplicate(in: componentDefinitionIDs) {
            throw CommandGeneratedIdentityError.duplicateComponentDefinitionIdentity(duplicate)
        }
        if let duplicate = firstDuplicate(in: componentInstanceIDs) {
            throw CommandGeneratedIdentityError.duplicateComponentInstanceIdentity(duplicate)
        }
        if let duplicate = firstDuplicate(in: patternArraySourceIDs) {
            throw CommandGeneratedIdentityError.duplicatePatternArraySourceIdentity(duplicate)
        }
    }

    private static func firstDuplicate<ID: Hashable>(in values: [ID]) -> ID? {
        var seen: Set<ID> = []
        return values.first { !seen.insert($0).inserted }
    }

    private static func generatedFeatureIDs(
        beforeIDs: Set<FeatureID>,
        after: DesignDocument
    ) throws -> [FeatureID] {
        var generated: [FeatureID] = []
        generated.reserveCapacity(after.cadDocument.designGraph.order.count)
        for featureID in after.cadDocument.designGraph.order {
            guard let feature = after.cadDocument.designGraph.nodes[featureID] else {
                throw CommandGeneratedIdentityError.missingFeature(featureID)
            }
            guard feature.id == featureID else {
                throw CommandGeneratedIdentityError.featureKeyMismatch(featureID)
            }
            if !beforeIDs.contains(featureID) {
                generated.append(featureID)
            }
        }
        return generated
    }

    private static func generatedBodyOutputs(
        featureIDs: [FeatureID],
        after: DesignDocument
    ) throws -> [GeneratedSourceBodyOutputIdentity] {
        var generated: [GeneratedSourceBodyOutputIdentity] = []
        for featureID in featureIDs {
            guard let feature = after.cadDocument.designGraph.nodes[featureID] else {
                throw CommandGeneratedIdentityError.missingFeature(featureID)
            }
            var seenRoles: Set<SourceBodyOutputRole> = []
            for output in feature.outputs where output.role == .body || output.role == .sheet {
                let identity = try GeneratedSourceBodyOutputIdentity(
                    featureID: featureID,
                    sourcePort: output.role
                )
                guard seenRoles.insert(identity.role).inserted else {
                    throw CommandGeneratedIdentityError.duplicateBodyOutput(
                        featureID,
                        identity.role
                    )
                }
                generated.append(identity)
            }
            if seenRoles.count > 1 {
                throw CommandGeneratedIdentityError.ambiguousBodyOutput(featureID)
            }
        }
        return generated
    }

    private static func generatedSceneNodeIDs(
        beforeIDs: Set<SceneNodeID>,
        after: DesignDocument
    ) throws -> [SceneNodeID] {
        let metadata = after.productMetadata
        var orderedIDs: [SceneNodeID] = []
        orderedIDs.reserveCapacity(metadata.sceneNodes.count)
        var visited: Set<SceneNodeID> = []
        var stack = Array(metadata.rootSceneNodeIDs.reversed())
        while let sceneNodeID = stack.popLast() {
            guard visited.insert(sceneNodeID).inserted else {
                throw CommandGeneratedIdentityError.duplicateSceneNode(sceneNodeID)
            }
            guard let sceneNode = metadata.sceneNodes[sceneNodeID] else {
                throw CommandGeneratedIdentityError.missingSceneNode(sceneNodeID)
            }
            guard sceneNode.id == sceneNodeID else {
                throw CommandGeneratedIdentityError.sceneNodeKeyMismatch(sceneNodeID)
            }
            orderedIDs.append(sceneNodeID)
            stack.append(contentsOf: sceneNode.childIDs.reversed())
        }
        guard visited.count == metadata.sceneNodes.count else {
            throw CommandGeneratedIdentityError.unreachableSceneNodes
        }
        return orderedIDs.filter { !beforeIDs.contains($0) }
    }

    private static func generatedComponentDefinitionIDs(
        beforeIDs: Set<ComponentDefinitionID>,
        after: DesignDocument
    ) throws -> [ComponentDefinitionID] {
        try after.productMetadata.componentDefinitions.keys.sorted().filter { id in
            guard after.productMetadata.componentDefinitions[id]?.id == id else {
                throw CommandGeneratedIdentityError.componentDefinitionKeyMismatch(id)
            }
            return !beforeIDs.contains(id)
        }
    }

    private static func generatedComponentInstanceIDs(
        beforeIDs: Set<ComponentInstanceID>,
        after: DesignDocument
    ) throws -> [ComponentInstanceID] {
        try after.productMetadata.componentInstances.keys.sorted().filter { id in
            guard after.productMetadata.componentInstances[id]?.id == id else {
                throw CommandGeneratedIdentityError.componentInstanceKeyMismatch(id)
            }
            return !beforeIDs.contains(id)
        }
    }

    private static func generatedPatternArraySourceIDs(
        beforeIDs: Set<PatternArraySourceID>,
        after: DesignDocument
    ) throws -> [PatternArraySourceID] {
        try after.productMetadata.patternArrays.keys.sorted().filter { id in
            guard after.productMetadata.patternArrays[id]?.id == id else {
                throw CommandGeneratedIdentityError.patternArraySourceKeyMismatch(id)
            }
            return !beforeIDs.contains(id)
        }
    }
}
