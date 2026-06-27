import SwiftCAD
import RupaCoreTypes

struct PatternArrayOwnershipResolver {
    func sourceID(
        owningOutputInstance componentInstanceID: ComponentInstanceID,
        in metadata: ProductMetadata
    ) -> PatternArraySourceID? {
        metadata.patternArrays.first { _, source in
            source.outputInstanceIDs.contains(componentInstanceID)
        }?.key
    }

    func sourceID(
        containingGeneratedOutputSceneNode sceneNodeID: SceneNodeID,
        in metadata: ProductMetadata
    ) -> PatternArraySourceID? {
        metadata.patternArrays.first { _, source in
            guard let rootNode = metadata.sceneNodes[source.rootSceneNodeID] else {
                return false
            }
            return rootNode.childIDs.contains { outputSceneNodeID in
                sceneSubtree(
                    outputSceneNodeID,
                    contains: sceneNodeID,
                    in: metadata
                )
            }
        }?.key
    }

    func sourceID(
        containingOutputSceneNode sceneNodeID: SceneNodeID,
        in metadata: ProductMetadata
    ) -> PatternArraySourceID? {
        metadata.patternArrays.first { _, source in
            guard let rootNode = metadata.sceneNodes[source.rootSceneNodeID] else {
                return false
            }
            if source.rootSceneNodeID == sceneNodeID {
                return true
            }
            return rootNode.childIDs.contains { outputSceneNodeID in
                sceneSubtree(
                    outputSceneNodeID,
                    contains: sceneNodeID,
                    in: metadata
                )
            }
        }?.key
    }

    private func sceneSubtree(
        _ rootSceneNodeID: SceneNodeID,
        contains targetSceneNodeID: SceneNodeID,
        in metadata: ProductMetadata
    ) -> Bool {
        var visitedSceneNodeIDs: Set<SceneNodeID> = []
        return sceneSubtree(
            rootSceneNodeID,
            contains: targetSceneNodeID,
            in: metadata,
            visitedSceneNodeIDs: &visitedSceneNodeIDs
        )
    }

    private func sceneSubtree(
        _ rootSceneNodeID: SceneNodeID,
        contains targetSceneNodeID: SceneNodeID,
        in metadata: ProductMetadata,
        visitedSceneNodeIDs: inout Set<SceneNodeID>
    ) -> Bool {
        guard visitedSceneNodeIDs.insert(rootSceneNodeID).inserted else {
            return false
        }
        if rootSceneNodeID == targetSceneNodeID {
            return true
        }
        guard let sceneNode = metadata.sceneNodes[rootSceneNodeID] else {
            return false
        }
        return sceneNode.childIDs.contains { childID in
            sceneSubtree(
                childID,
                contains: targetSceneNodeID,
                in: metadata,
                visitedSceneNodeIDs: &visitedSceneNodeIDs
            )
        }
    }
}
