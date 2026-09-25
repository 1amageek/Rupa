import RupaCore

/// Checked parent frames shared with document transform and hierarchy commands.
package struct ViewportSceneNodeParentFrames: Sendable {
    private let hierarchy: SceneNodeHierarchy

    package init(document: DesignDocument) throws {
        do {
            hierarchy = try SceneNodeHierarchy(metadata: document.productMetadata)
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            throw RealityViewportSpatialBatch.invalid(String(describing: error))
        }
    }

    /// An absent node has no command target; an invalid retained frame is a failure.
    package func parentWorldTransform(of sceneNodeID: SceneNodeID) throws -> Transform3D? {
        guard hierarchy.node(sceneNodeID) != nil else { return nil }
        do {
            return try hierarchy.parentWorldTransform(of: sceneNodeID)
        } catch {
            throw RealityViewportSpatialBatch.invalid(String(describing: error))
        }
    }
}
