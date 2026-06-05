import Foundation
import SwiftCAD

public struct SceneNode: Codable, Hashable, Identifiable, Sendable {
    public var id: SceneNodeID
    public var name: String
    public var reference: SceneNodeReference?
    public var object: ObjectDescriptor?
    public var childIDs: [SceneNodeID]
    public var isVisible: Bool
    public var isLocked: Bool
    public var localTransform: Transform3D
    public var materialID: MaterialID?

    public init(
        id: SceneNodeID = SceneNodeID(),
        name: String,
        reference: SceneNodeReference? = nil,
        object: ObjectDescriptor? = nil,
        childIDs: [SceneNodeID] = [],
        isVisible: Bool = true,
        isLocked: Bool = false,
        localTransform: Transform3D = .identity,
        materialID: MaterialID? = nil
    ) {
        self.id = id
        self.name = name
        self.reference = reference
        self.object = object
        self.childIDs = childIDs
        self.isVisible = isVisible
        self.isLocked = isLocked
        self.localTransform = localTransform
        self.materialID = materialID
    }

    public func validate() throws {
        guard !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw DocumentValidationError.invalidProductMetadata("Scene node names must not be empty.")
        }
        guard Set(childIDs).count == childIDs.count else {
            throw DocumentValidationError.invalidProductMetadata("Scene node child references must be unique.")
        }
        try reference?.validate()
        try object?.validate()
        try localTransform.validate()
    }
}
