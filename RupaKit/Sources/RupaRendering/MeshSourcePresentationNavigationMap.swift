import RupaCore
import RupaCoreTypes

/// An occurrence-native navigation mapping supplied by the project scene
/// owner. The sequence form lets the boundary reject duplicate mappings.
public struct MeshSourcePresentationNavigationMap: Sendable {
    private let sceneNodeIDsByOccurrence: [SceneOccurrenceID: SceneNodeID]

    public init(
        mappings: [(occurrenceID: SceneOccurrenceID, sceneNodeID: SceneNodeID)]
    ) throws {
        var sceneNodeIDsByOccurrence: [SceneOccurrenceID: SceneNodeID] = [:]
        sceneNodeIDsByOccurrence.reserveCapacity(mappings.count)
        for mapping in mappings {
            do {
                try mapping.occurrenceID.validate()
            } catch let error as EditorError {
                throw MeshSourcePresentationPickError(
                    code: .invalidIdentity,
                    message: error.message
                )
            }
            guard sceneNodeIDsByOccurrence[mapping.occurrenceID] == nil else {
                throw MeshSourcePresentationPickError(
                    code: .duplicateNavigationMapping,
                    message: "Presentation navigation requires one owner per original occurrence."
                )
            }
            sceneNodeIDsByOccurrence[mapping.occurrenceID] = mapping.sceneNodeID
        }
        self.sceneNodeIDsByOccurrence = sceneNodeIDsByOccurrence
    }

    public var count: Int {
        sceneNodeIDsByOccurrence.count
    }

    public func sceneNodeID(
        for occurrenceID: SceneOccurrenceID
    ) -> SceneNodeID? {
        sceneNodeIDsByOccurrence[occurrenceID]
    }
}
