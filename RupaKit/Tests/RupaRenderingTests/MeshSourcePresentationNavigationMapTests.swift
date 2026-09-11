import RupaCore
import RupaCoreTypes
import RupaProjectModel
import RupaViewportScene
import Testing
@testable import RupaRendering

@Test(.timeLimit(.minutes(1)))
func meshSourcePresentationNavigationMapResolvesEveryOccurrenceItAccepts() throws {
    let occurrenceIDs = (0..<3).map {
        SceneOccurrenceID(rawValue: "occurrence.presentation-navigation.\($0)")
    }
    let sceneNodeIDs = occurrenceIDs.map { _ in SceneNodeID() }
    let navigation = try MeshSourcePresentationNavigationMap(
        mappings: zip(occurrenceIDs, sceneNodeIDs).map {
            (occurrenceID: $0, sceneNodeID: $1)
        }
    )

    #expect(navigation.count == occurrenceIDs.count)
    for (occurrenceID, sceneNodeID) in zip(occurrenceIDs, sceneNodeIDs) {
        #expect(navigation.sceneNodeID(for: occurrenceID) == sceneNodeID)
    }
    #expect(
        navigation.sceneNodeID(
            for: SceneOccurrenceID(rawValue: "occurrence.presentation-navigation.absent")
        ) == nil
    )
}

@Test(.timeLimit(.minutes(1)))
func meshSourcePresentationNavigationMapRejectsInvalidAndDuplicatedOccurrences() throws {
    var invalidError: MeshSourcePresentationPickError?
    do {
        _ = try MeshSourcePresentationNavigationMap(
            mappings: [
                (occurrenceID: SceneOccurrenceID(rawValue: ""), sceneNodeID: SceneNodeID()),
            ]
        )
    } catch let error as MeshSourcePresentationPickError {
        invalidError = error
    }
    #expect(invalidError?.code == .invalidIdentity)

    let occurrenceID = SceneOccurrenceID(rawValue: "occurrence.presentation-navigation.0")
    var duplicateError: MeshSourcePresentationPickError?
    do {
        _ = try MeshSourcePresentationNavigationMap(
            mappings: [
                (occurrenceID: occurrenceID, sceneNodeID: SceneNodeID()),
                (occurrenceID: occurrenceID, sceneNodeID: SceneNodeID()),
            ]
        )
    } catch let error as MeshSourcePresentationPickError {
        duplicateError = error
    }
    #expect(duplicateError?.code == .duplicateNavigationMapping)
}
