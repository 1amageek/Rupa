import Foundation
import RupaCore
import RupaViewportScene

/// One real presentation occurrence and its immutable placement baseline.
struct ViewportObjectTransformMember: Sendable {
    let occurrenceID: String
    let reference: SceneNodeReference
    let sceneNodeID: SceneNodeID
    let baseLocalTransform: Transform3D
    let parentWorldTransform: Transform3D
    let bounds: ViewportObjectEditState
}
