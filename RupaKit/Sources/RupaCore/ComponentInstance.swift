import Foundation
import SwiftCAD

public struct ComponentInstance: Codable, Hashable, Identifiable, Sendable {
    public var id: ComponentInstanceID
    public var definitionID: ComponentDefinitionID
    public var name: String
    public var localTransform: Transform3D
    public var isVisible: Bool
    public var isLocked: Bool
    public var properties: [String: String]

    public init(
        id: ComponentInstanceID = ComponentInstanceID(),
        definitionID: ComponentDefinitionID,
        name: String,
        localTransform: Transform3D = .identity,
        isVisible: Bool = true,
        isLocked: Bool = false,
        properties: [String: String] = [:]
    ) {
        self.id = id
        self.definitionID = definitionID
        self.name = name
        self.localTransform = localTransform
        self.isVisible = isVisible
        self.isLocked = isLocked
        self.properties = properties
    }

    public func validate() throws {
        guard !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw DocumentValidationError.invalidProductMetadata("Component instance names must not be empty.")
        }
        try localTransform.validate()
        try validateProperties(properties, owner: "component instance")
    }
}
