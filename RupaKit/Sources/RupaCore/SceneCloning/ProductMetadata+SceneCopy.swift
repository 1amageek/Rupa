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

    /// Why Copy with Placement cannot copy `ids`: what copying refuses, and component instances,
    /// which Copy with Placement does not copy (realize them first).
    public func placementCopyRefusal(for ids: [SceneNodeID]) -> EditorError? {
        if let refusal = sceneCopyRefusal(for: ids) {
            return refusal
        }
        var pending = ids
        var visited: Set<SceneNodeID> = []
        while let id = pending.popLast() {
            guard visited.insert(id).inserted, let node = sceneNodes[id] else { continue }
            if node.reference?.kind == .componentInstance {
                return EditorError(
                    code: .commandInvalid,
                    message: "Copy with Placement does not copy instances; realize them first."
                )
            }
            pending.append(contentsOf: node.childIDs)
        }
        return nil
    }

    /// Nodes whose sharing semantics are not a copy are refused rather than silently shared.
    func sceneCopyRefusal(forNode id: SceneNodeID) -> EditorError? {
        guard sceneNodes[id] != nil else {
            return EditorError(code: .referenceUnresolved, message: "Scene node \(id.description) to copy does not exist.")
        }
        if PatternArrayOwnershipResolver().sourceID(containingOutputSceneNode: id, in: self) != nil {
            return EditorError(code: .commandInvalid, message: "Pattern array outputs are copied by exploding the array first.")
        }
        return nil
    }
}
