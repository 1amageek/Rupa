import Foundation
import SwiftCAD

public struct RupaSceneNode: Codable, Hashable, Identifiable, Sendable {
    public var id: RupaSceneNodeID
    public var name: String
    public var reference: RupaSceneNodeReference?
    public var childIDs: [RupaSceneNodeID]
    public var isVisible: Bool
    public var isLocked: Bool
    public var localTransform: Transform3D
    public var materialID: MaterialID?

    public init(
        id: RupaSceneNodeID = RupaSceneNodeID(),
        name: String,
        reference: RupaSceneNodeReference? = nil,
        childIDs: [RupaSceneNodeID] = [],
        isVisible: Bool = true,
        isLocked: Bool = false,
        localTransform: Transform3D = .identity,
        materialID: MaterialID? = nil
    ) {
        self.id = id
        self.name = name
        self.reference = reference
        self.childIDs = childIDs
        self.isVisible = isVisible
        self.isLocked = isLocked
        self.localTransform = localTransform
        self.materialID = materialID
    }

    public func validate() throws {
        guard !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw RupaDocumentValidationError.invalidProductMetadata("Scene node names must not be empty.")
        }
        guard Set(childIDs).count == childIDs.count else {
            throw RupaDocumentValidationError.invalidProductMetadata("Scene node child references must be unique.")
        }
        try reference?.validate()
        try localTransform.validate()
    }
}
