import Foundation
import SwiftCAD

public struct RupaComponentDefinition: Codable, Hashable, Identifiable, Sendable {
    public var id: RupaComponentDefinitionID
    public var name: String
    public var rootSceneNodeIDs: [RupaSceneNodeID]
    public var properties: [String: String]

    public init(
        id: RupaComponentDefinitionID = RupaComponentDefinitionID(),
        name: String,
        rootSceneNodeIDs: [RupaSceneNodeID] = [],
        properties: [String: String] = [:]
    ) {
        self.id = id
        self.name = name
        self.rootSceneNodeIDs = rootSceneNodeIDs
        self.properties = properties
    }

    public func validate() throws {
        guard !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw RupaDocumentValidationError.invalidProductMetadata("Component definition names must not be empty.")
        }
        guard Set(rootSceneNodeIDs).count == rootSceneNodeIDs.count else {
            throw RupaDocumentValidationError.invalidProductMetadata(
                "Component definition root scene node references must be unique."
            )
        }
        try validateProperties(properties, owner: "component definition")
    }
}
