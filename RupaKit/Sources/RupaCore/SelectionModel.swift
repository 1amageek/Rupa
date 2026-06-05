import Foundation

public struct SelectionModel: Codable, Equatable, Sendable {
    public private(set) var selectedSceneNodeIDs: [RupaSceneNodeID]
    public private(set) var hoveredSceneNodeID: RupaSceneNodeID?

    public var primarySceneNodeID: RupaSceneNodeID? {
        selectedSceneNodeIDs.last
    }

    public init(
        selectedSceneNodeIDs: [RupaSceneNodeID] = [],
        hoveredSceneNodeID: RupaSceneNodeID? = nil
    ) {
        self.selectedSceneNodeIDs = selectedSceneNodeIDs
        self.hoveredSceneNodeID = hoveredSceneNodeID
    }

    public static var empty: SelectionModel {
        SelectionModel()
    }

    public func containsSceneNode(_ id: RupaSceneNodeID) -> Bool {
        selectedSceneNodeIDs.contains(id)
    }

    public mutating func selectSceneNode(
        _ id: RupaSceneNodeID?,
        in document: RupaDocument
    ) throws {
        guard let id else {
            clearSelection()
            return
        }
        try validateSceneNode(id, in: document)
        selectedSceneNodeIDs = [id]
    }

    public mutating func selectSceneNodes(
        _ ids: [RupaSceneNodeID],
        in document: RupaDocument
    ) throws {
        var uniqueIDs: [RupaSceneNodeID] = []
        var seenIDs: Set<RupaSceneNodeID> = []
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
        _ id: RupaSceneNodeID?,
        in document: RupaDocument
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

    public mutating func pruneMissingReferences(in document: RupaDocument) {
        selectedSceneNodeIDs = selectedSceneNodeIDs.filter { id in
            document.productMetadata.sceneNodes[id] != nil
        }
        if let hoveredSceneNodeID,
           document.productMetadata.sceneNodes[hoveredSceneNodeID] == nil {
            self.hoveredSceneNodeID = nil
        }
    }

    public func selectedSceneNodeReferences(in document: RupaDocument) -> [RupaSceneNodeReference] {
        selectedSceneNodeIDs.compactMap { id in
            document.productMetadata.sceneNodes[id]?.reference
        }
    }

    private func validateSceneNode(
        _ id: RupaSceneNodeID,
        in document: RupaDocument
    ) throws {
        guard document.productMetadata.sceneNodes[id] != nil else {
            throw RupaError(
                code: .referenceUnresolved,
                message: "Selection references a missing scene node."
            )
        }
    }
}
