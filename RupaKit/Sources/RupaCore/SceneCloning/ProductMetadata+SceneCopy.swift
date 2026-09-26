import SwiftCAD
import RupaCoreTypes

extension ProductMetadata {
    /// Why the objects `ids` cannot be copied, or `nil` when Duplicate, Place and Copy with
    /// Placement accept them.
    ///
    /// Copy commands refuse a whole selection rather than trimming it, so the controls that offer
    /// copying read this same answer.
    public func sceneCopyRefusal(for ids: [SceneNodeID]) -> EditorError? {
        guard !ids.isEmpty else {
            return EditorError(code: .commandInvalid, message: "Copying requires at least one scene node.")
        }
        let rootIDs = Set(rootSceneNodeIDs)
        var pending = ids
        var visited: Set<SceneNodeID> = []
        for id in ids where rootIDs.contains(id) {
            return EditorError(code: .commandInvalid, message: "A document root is not copied; copy the objects inside it.")
        }
        while let id = pending.popLast() {
            guard visited.insert(id).inserted else { continue }
            if let refusal = sceneCopyRefusal(forNode: id) {
                return refusal
            }
            pending.append(contentsOf: sceneNodes[id]?.childIDs ?? [])
        }
        return nil
    }

    /// Nodes whose sharing semantics are not a copy are refused rather than silently shared.
    func sceneCopyRefusal(forNode id: SceneNodeID) -> EditorError? {
        guard let node = sceneNodes[id] else {
            return EditorError(code: .referenceUnresolved, message: "Scene node \(id.description) to copy does not exist.")
        }
        if PatternArrayOwnershipResolver().sourceID(containingOutputSceneNode: id, in: self) != nil {
            return EditorError(code: .commandInvalid, message: "Pattern array outputs are copied by exploding the array first.")
        }
        // FIXME(INCOMPLETE_IMPLEMENTATION): A saved measurement is refused because a scene fragment
        // carries its annotation node but not the measurement (its distance and anchors), and its
        // anchors may name geometry outside the copy. Production path: Duplicate, Place, Copy with
        // Placement and independent-copy pattern arrays, including a Measurements group. Completion
        // requires carrying the measurement with its anchors remapped onto the copied geometry.
        if measurements.values.contains(where: { $0.sceneNodeID == id }) {
            return EditorError(code: .commandInvalid, message: "Saved measurements are not copied; measure the copy again.")
        }
        switch node.reference?.kind {
        // FIXME(INCOMPLETE_IMPLEMENTATION): Construction geometry is refused because copying would
        // share its source instead of duplicating it. Production path: Duplicate, Place, Copy with
        // Placement and independent-copy pattern arrays. Completion requires cloning the
        // construction source under a new identity.
        case .construction:
            return EditorError(code: .commandInvalid, message: "Copying construction geometry is not supported yet.")
        case .feature, .body, .sketch, .componentInstance, .authoredMesh, nil:
            return nil
        }
    }
}
