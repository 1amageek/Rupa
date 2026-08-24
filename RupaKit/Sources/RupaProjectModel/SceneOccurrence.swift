import Foundation
import RupaCoreTypes
import RupaGeometry

public struct SceneOccurrence: Codable, Equatable, Sendable {
    public var id: SceneOccurrenceID
    public var definitionID: ObjectDefinitionID
    public var parentID: SceneOccurrenceID?
    public var localTransform: GeometryTransform3D

    public init(
        id: SceneOccurrenceID,
        definitionID: ObjectDefinitionID,
        parentID: SceneOccurrenceID? = nil,
        localTransform: GeometryTransform3D = .identity
    ) {
        self.id = id
        self.definitionID = definitionID
        self.parentID = parentID
        self.localTransform = localTransform
    }

    public func validate() throws {
        do {
            try id.validate()
            try definitionID.validate()
            try parentID?.validate()
        } catch let error as EditorError {
            throw ProjectModelError(code: .invalidIdentity, message: error.message)
        }
        if parentID == id {
            throw ProjectModelError(code: .hierarchyCycle, message: "Scene occurrences cannot parent themselves.")
        }
        guard localTransform.values.count == 16,
              localTransform.values.allSatisfy(\.isFinite) else {
            throw ProjectModelError(code: .invalidTransform, message: "Scene occurrence transforms must be finite 4x4 matrices.")
        }
    }
}
