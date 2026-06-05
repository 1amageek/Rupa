import Foundation

public struct SelectionModel: Codable, Equatable, Sendable {
    public private(set) var selectedSceneNodeIDs: [SceneNodeID]
    public private(set) var hoveredSceneNodeID: SceneNodeID?

    public var primarySceneNodeID: SceneNodeID? {
        selectedSceneNodeIDs.last
    }

    public init(
        selectedSceneNodeIDs: [SceneNodeID] = [],
        hoveredSceneNodeID: SceneNodeID? = nil
    ) {
        self.selectedSceneNodeIDs = selectedSceneNodeIDs
        self.hoveredSceneNodeID = hoveredSceneNodeID
    }

    public static var empty: SelectionModel {
        SelectionModel()
    }

    public func containsSceneNode(_ id: SceneNodeID) -> Bool {
        selectedSceneNodeIDs.contains(id)
    }

    public mutating func selectSceneNode(
        _ id: SceneNodeID?,
        in document: DesignDocument
    ) throws {
        guard let id else {
            clearSelection()
            return
        }
        try validateSceneNode(id, in: document)
        selectedSceneNodeIDs = [id]
    }

    public mutating func selectSceneNodes(
        _ ids: [SceneNodeID],
        in document: DesignDocument
    ) throws {
        var uniqueIDs: [SceneNodeID] = []
        var seenIDs: Set<SceneNodeID> = []
        for id in ids {
            guard seenIDs.insert(id).inserted else {
                continue
            }
            try validateSceneNode(id, in: document)
            uniqueIDs.append(id)
        }
        selectedSceneNodeIDs = uniqueIDs
    }

    public mutating func hoverSceneNode(
        _ id: SceneNodeID?,
        in document: DesignDocument
    ) throws {
        guard let id else {
            hoveredSceneNodeID = nil
            return
        }
        try validateSceneNode(id, in: document)
        hoveredSceneNodeID = id
    }

    public mutating func clearSelection() {
        selectedSceneNodeIDs = []
    }

    public mutating func clearHover() {
        hoveredSceneNodeID = nil
    }

    public mutating func pruneMissingReferences(in document: DesignDocument) {
        selectedSceneNodeIDs = selectedSceneNodeIDs.filter { id in
            document.productMetadata.sceneNodes[id] != nil
        }
        if let hoveredSceneNodeID,
           document.productMetadata.sceneNodes[hoveredSceneNodeID] == nil {
            self.hoveredSceneNodeID = nil
        }
    }

    public func selectedSceneNodeReferences(in document: DesignDocument) -> [SceneNodeReference] {
        selectedSceneNodeIDs.compactMap { id in
            document.productMetadata.sceneNodes[id]?.reference
        }
    }

    private func validateSceneNode(
        _ id: SceneNodeID,
        in document: DesignDocument
    ) throws {
        guard document.productMetadata.sceneNodes[id] != nil else {
            throw EditorError(
                code: .referenceUnresolved,
                message: "Selection references a missing scene node."
            )
        }
    }
}
