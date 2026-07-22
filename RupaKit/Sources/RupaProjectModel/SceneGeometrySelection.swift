import Foundation
import RupaGeometry

public struct SceneGeometrySelection: Codable, Equatable, Hashable, Sendable {
    public var occurrenceID: SceneOccurrenceID
    public var element: MeshSelectionElement

    public init(
        occurrenceID: SceneOccurrenceID,
        element: MeshSelectionElement
    ) {
        self.occurrenceID = occurrenceID
        self.element = element
    }

    public func validate(in project: ProjectSourceModel) throws {
        try occurrenceID.validate()
        guard project.occurrences[occurrenceID] != nil else {
            throw ProjectModelError(
                code: .invalidReference,
                message: "Scene geometry selection references a missing occurrence."
            )
        }
    }
}
