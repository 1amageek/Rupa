import Foundation
import SwiftCAD

public struct ComponentDefinition: Codable, Hashable, Identifiable, Sendable {
    public var id: ComponentDefinitionID
    public var name: String
    public var rootSceneNodeIDs: [SceneNodeID]
    public var properties: [String: String]

    public init(
        id: ComponentDefinitionID = ComponentDefinitionID(),
        name: String,
        rootSceneNodeIDs: [SceneNodeID] = [],
        properties: [String: String] = [:]
    ) {
        self.id = id
        self.name = name
        self.rootSceneNodeIDs = rootSceneNodeIDs
        self.properties = properties
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
        try validateProperties(properties, owner: "component definition")
    }
}
