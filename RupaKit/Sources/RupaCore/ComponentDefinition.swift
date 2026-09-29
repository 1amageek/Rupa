import Foundation
import SwiftCAD

public struct ComponentDefinition: Codable, Hashable, Identifiable, Sendable {
    public var id: ComponentDefinitionID
    public var name: String
    public var rootSceneNodeIDs: [SceneNodeID]
    /// Definition-owned root placement, independent of the source node's scene placement.
    public struct RootPlacement: Codable, Hashable, Sendable {
        public var transform: Transform3D
        public var isVisible: Bool

        public init(transform: Transform3D, isVisible: Bool) {
            self.transform = transform
            self.isVisible = isVisible
        }
    }

    /// Nil occurs only in legacy payloads, normalized by ProductMetadata.
    public var rootPlacements: [SceneNodeID: RootPlacement]?
    public var properties: [String: String]

    public init(
        id: ComponentDefinitionID = ComponentDefinitionID(),
        name: String,
        rootSceneNodeIDs: [SceneNodeID] = [],
        properties: [String: String] = [:],
        rootPlacements: [SceneNodeID: RootPlacement]? = nil
    ) {
        self.id = id
        self.name = name
        self.rootSceneNodeIDs = rootSceneNodeIDs
        self.properties = properties
        self.rootPlacements = rootPlacements
    }

    public func rootPlacement(for id: SceneNodeID) throws -> RootPlacement {
        guard let placement = rootPlacements?[id] else {
            throw DocumentValidationError.invalidProductMetadata("Component definition is missing an owned root placement.")
        }
        return placement
    }

    public func validate() throws {
        guard !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw DocumentValidationError.invalidProductMetadata("Component definition names must not be empty.")
        }
        guard Set(rootSceneNodeIDs).count == rootSceneNodeIDs.count else {
            throw DocumentValidationError.invalidProductMetadata(
                "Component definition root scene node references must be unique."
            )
        }
        guard let rootPlacements, Set(rootPlacements.keys) == Set(rootSceneNodeIDs) else {
            throw DocumentValidationError.invalidProductMetadata("Component root placements must cover exactly its roots.")
        }
        for placement in rootPlacements.values { try placement.transform.validateAffinePlacement() }
        try validateProperties(properties, owner: "component definition")
    }
}
