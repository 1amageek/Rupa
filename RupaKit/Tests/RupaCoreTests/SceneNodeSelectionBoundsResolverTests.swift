import Foundation
import SwiftCAD
import Testing
@testable import RupaCore

@Suite struct SceneNodeNameAllocatorTests {
    @Test func aFreeNameIsUsedAsGiven() throws {
        let existingNode = SceneNode(name: "Existing")
        let metadata = ProductMetadata(
            sceneNodes: [existingNode.id: existingNode],
            rootSceneNodeIDs: [existingNode.id]
        )

        #expect(
            SceneNodeNameAllocator().uniqueName(base: "Group", in: metadata) == "Group"
        )
    }

    @Test func aTakenNameIsNumberedUntilItIsFree() throws {
        let group = SceneNode(name: "Group")
        let groupTwo = SceneNode(name: "Group 2")
        let metadata = ProductMetadata(
            sceneNodes: [group.id: group, groupTwo.id: groupTwo],
            rootSceneNodeIDs: [group.id, groupTwo.id]
        )

        #expect(
            SceneNodeNameAllocator().uniqueName(base: "Group", in: metadata) == "Group 3"
        )
    }
}
