import Foundation
import RupaCore
import RupaProject

enum OutlinerVisibilityFilter: String, CaseIterable, Identifiable, Sendable {
    case all
    case visible
    case hidden
    case locked
    case unlocked

    var id: Self { self }

    var title: String {
        switch self {
        case .all: "All"
        case .visible: "Visible"
        case .hidden: "Hidden"
        case .locked: "Locked"
        case .unlocked: "Unlocked"
        }
    }
}

enum OutlinerIntent: Equatable, Sendable {
    case select([SceneNodeID])
    case hover(SceneNodeID?, isHovered: Bool)
    case rename(id: SceneNodeID, name: String)
    case setVisibility(ids: [SceneNodeID], isVisible: Bool)
    case setLock(ids: [SceneNodeID], isLocked: Bool)
    case isolate(ids: [SceneNodeID])
    case showAll
    case frameCurrentSelection
    case move(
        ids: [SceneNodeID],
        parentID: SceneNodeID?,
        beforeSiblingID: SceneNodeID?,
        expectedGeneration: DocumentGeneration
    )
    case group(ids: [SceneNodeID])
    case ungroup(ids: [SceneNodeID])
    case delete(ids: [SceneNodeID])
}

struct OutlinerMoveDragSession: Equatable, Sendable {
    let nonce: UUID
    let ids: [SceneNodeID]
    let expectedGeneration: DocumentGeneration

    static func payload(for nonce: UUID) -> Data {
        Data(nonce.uuidString.utf8)
    }

    static func nonce(from payload: Data) -> UUID? {
        guard payload.count == 36 else { return nil }
        let string = String(decoding: payload, as: UTF8.self)
        guard string.count == 36,
              let nonce = UUID(uuidString: string),
              nonce.uuidString.caseInsensitiveCompare(string) == .orderedSame else {
            return nil
        }
        return nonce
    }

    func matches(
        nonce: UUID?,
        generation: DocumentGeneration
    ) -> Bool {
        self.nonce == nonce
            && expectedGeneration == generation
    }
}

struct OutlinerDropDestination: Equatable, Sendable {
    let parentID: SceneNodeID?
    let beforeSiblingID: SceneNodeID?
}

struct OutlinerRow: Identifiable, Equatable, Sendable {
    let id: SceneNodeID
    let parentID: SceneNodeID?
    let depth: Int
    let name: String
    let kindTitle: String
    let isVisible: Bool
    let isEffectivelyVisible: Bool
    let isLocked: Bool
    let hasChildren: Bool
    let isExpanded: Bool
    let isGeneratedOutput: Bool
    let isPatternRoot: Bool
    let isComponentInstance: Bool
    let canRename: Bool
    let canMutateState: Bool
    let disabledReason: String?

    var systemImage: String {
        if isPatternRoot { return "square.grid.3x3" }
        if isComponentInstance { return "square.stack.3d.up" }
        switch kindTitle {
        case "Body": return "cube"
        case "Authored Mesh": return "cube.transparent"
        case "Sketch": return "pencil.and.outline"
        case "Construction": return "ruler"
        case "Feature": return "gearshape"
        default: return "folder"
        }
    }
}

struct OutlinerProjection: Equatable, Sendable {
    let rows: [OutlinerRow]
    let allRows: [OutlinerRow]
    let rowsByID: [SceneNodeID: OutlinerRow]
    let canMutateIDSet: Set<SceneNodeID>

    init(rows: [OutlinerRow], allRows: [OutlinerRow]) {
        self.rows = rows
        self.allRows = allRows
        self.rowsByID = Dictionary(uniqueKeysWithValues: allRows.map { ($0.id, $0) })
        self.canMutateIDSet = Set(allRows.lazy.filter(\.canMutateState).map(\.id))
    }

    func row(for id: SceneNodeID) -> OutlinerRow? {
        rowsByID[id]
    }

    func canMutate(ids: [SceneNodeID]) -> Bool {
        !ids.isEmpty && Set(ids).isSubset(of: canMutateIDSet)
    }

    func canMutate(ids: Set<SceneNodeID>) -> Bool {
        !ids.isEmpty && ids.isSubset(of: canMutateIDSet)
    }

    func canMove(ids: [SceneNodeID]) -> Bool {
        !ids.isEmpty
            && Set(ids).count == ids.count
            && ids.allSatisfy { id in
                guard let row = rowsByID[id] else { return false }
                return row.canMutateState && !row.isLocked && !row.isPatternRoot
            }
    }

    static func canReceiveChildren(_ row: OutlinerRow) -> Bool {
        !row.isLocked && !row.isGeneratedOutput && !row.isPatternRoot
    }

    static func contextSelection(
        rowID: SceneNodeID,
        selectedIDs: Set<SceneNodeID>,
        orderedIDs: [SceneNodeID]
    ) -> [SceneNodeID] {
        if selectedIDs.contains(rowID) {
            return orderedIDs.filter { selectedIDs.contains($0) }
        }
        return [rowID]
    }

    static func normalizedRename(_ draft: String) -> String? {
        let normalized = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        return normalized.isEmpty ? nil : normalized
    }

    static func frameSelectionIsEnabled(
        rowID: SceneNodeID,
        selectedIDs: Set<SceneNodeID>,
        canFrameSelection: Bool
    ) -> Bool {
        canFrameSelection && selectedIDs.contains(rowID)
    }

    static func make(
        metadata: ProductMetadata,
        expandedIDs: Set<SceneNodeID>,
        searchText: String,
        filter: OutlinerVisibilityFilter
    ) -> OutlinerProjection {
        let ownership = OwnershipIndex(metadata: metadata)
        var ordered: [NodeRecord] = []
        var parentByID: [SceneNodeID: SceneNodeID] = [:]
        var visited: Set<SceneNodeID> = []

        func visit(
            _ id: SceneNodeID,
            depth: Int,
            parentID: SceneNodeID?,
            inheritedVisibility: Bool
        ) {
            guard visited.insert(id).inserted,
                  let node = metadata.sceneNodes[id] else {
                return
            }
            if node.reference?.kind == .sketch,
               node.isVisible == false,
               parentID.flatMap({ metadata.sceneNodes[$0]?.reference?.kind }) == .some(.body) {
                return
            }
            if let parentID {
                parentByID[id] = parentID
            }
            let effectiveVisibility = inheritedVisibility && node.isVisible
            let record = NodeRecord(
                id: id,
                parentID: parentID,
                depth: depth,
                name: node.name,
                kindTitle: kindTitle(for: node),
                isVisible: node.isVisible,
                isEffectivelyVisible: effectiveVisibility,
                isLocked: node.isLocked,
                childIDs: node.childIDs,
                isGeneratedOutput: ownership.generatedNodeIDs.contains(id),
                isPatternRoot: ownership.patternRootIDs.contains(id),
                isComponentInstance: node.reference?.componentInstanceID != nil
                    || node.object?.componentInstanceID != nil
            )
            ordered.append(record)
            for childID in node.childIDs {
                visit(
                    childID,
                    depth: depth + 1,
                    parentID: id,
                    inheritedVisibility: effectiveVisibility
                )
            }
        }

        for rootID in metadata.rootSceneNodeIDs {
            visit(rootID, depth: 0, parentID: nil, inheritedVisibility: true)
        }

        let normalizedQuery = searchText
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
        let stateMatches: (NodeRecord) -> Bool = { record in
            switch filter {
            case .all: true
            case .visible: record.isVisible
            case .hidden: !record.isVisible
            case .locked: record.isLocked
            case .unlocked: !record.isLocked
            }
        }
        let textMatches: (NodeRecord) -> Bool = { record in
            guard !normalizedQuery.isEmpty else { return true }
            return record.name.folding(
                options: [.caseInsensitive, .diacriticInsensitive],
                locale: .current
            ).localizedCaseInsensitiveContains(normalizedQuery)
                || record.kindTitle.localizedCaseInsensitiveContains(normalizedQuery)
        }

        let isFiltered = !normalizedQuery.isEmpty || filter != .all
        let matchedIDs = Set(
            ordered.lazy.filter { stateMatches($0) && textMatches($0) }.map(\.id)
        )
        var includedIDs = Set<SceneNodeID>()
        if isFiltered {
            for id in matchedIDs {
                var current: SceneNodeID? = id
                while let currentID = current {
                    guard includedIDs.insert(currentID).inserted else { break }
                    current = parentByID[currentID]
                }
            }
        } else {
            includedIDs = Set(ordered.map(\.id))
        }

        var ancestorExpansion: Set<SceneNodeID> = []
        if isFiltered {
            for id in includedIDs {
                var current = parentByID[id]
                while let parentID = current {
                    guard ancestorExpansion.insert(parentID).inserted else { break }
                    current = parentByID[parentID]
                }
            }
        }

        var allRows: [OutlinerRow] = []
        var rows: [OutlinerRow] = []
        for record in ordered {
            let isExpanded = expandedIDs.contains(record.id)
                || (isFiltered && ancestorExpansion.contains(record.id))
            let canRename = !record.isGeneratedOutput
            let canMutateState = !record.isGeneratedOutput
            let disabledReason = record.isGeneratedOutput
                ? "Generated pattern output is controlled by its pattern root."
                : nil
            let row = OutlinerRow(
                id: record.id,
                parentID: record.parentID,
                depth: record.depth,
                name: record.name,
                kindTitle: record.kindTitle,
                isVisible: record.isVisible,
                isEffectivelyVisible: record.isEffectivelyVisible,
                isLocked: record.isLocked,
                hasChildren: !record.childIDs.isEmpty,
                isExpanded: isExpanded,
                isGeneratedOutput: record.isGeneratedOutput,
                isPatternRoot: record.isPatternRoot,
                isComponentInstance: record.isComponentInstance,
                canRename: canRename,
                canMutateState: canMutateState,
                disabledReason: disabledReason
            )
            allRows.append(row)
        }

        var renderedByID: [SceneNodeID: Bool] = [:]
        var expandedByID: [SceneNodeID: Bool] = [:]
        for row in allRows {
            let included = includedIDs.contains(row.id)
            let parentID = parentByID[row.id]
            let parentRendered = parentID.map { renderedByID[$0] ?? false } ?? true
            let parentExpanded = parentID.map { expandedByID[$0] ?? false } ?? true
            if included && parentRendered && parentExpanded {
                rows.append(row)
            }
            renderedByID[row.id] = included && parentRendered && parentExpanded
            expandedByID[row.id] = row.isExpanded
        }
        return OutlinerProjection(rows: rows, allRows: allRows)
    }

    private struct NodeRecord {
        let id: SceneNodeID
        let parentID: SceneNodeID?
        let depth: Int
        let name: String
        let kindTitle: String
        let isVisible: Bool
        let isEffectivelyVisible: Bool
        let isLocked: Bool
        let childIDs: [SceneNodeID]
        let isGeneratedOutput: Bool
        let isPatternRoot: Bool
        let isComponentInstance: Bool
    }

    static func dropDestination(
        rowID: SceneNodeID,
        locationY: Double,
        rowHeight: Double = 22.0,
        metadata: ProductMetadata
    ) -> OutlinerDropDestination? {
        guard locationY.isFinite, rowHeight.isFinite, rowHeight > 0,
              metadata.sceneNodes[rowID] != nil else {
            return nil
        }
        let parentByID = parentIDs(in: metadata)
        let parentID = parentByID[rowID]
        let siblings = parentID.flatMap { metadata.sceneNodes[$0]?.childIDs }
            ?? metadata.rootSceneNodeIDs
        return dropDestination(
            rowID: rowID,
            parentID: parentID,
            siblingIDs: siblings,
            locationY: locationY,
            rowHeight: rowHeight,
            metadata: metadata
        )
    }

    static func dropDestination(
        rowID: SceneNodeID,
        parentID: SceneNodeID?,
        siblingIDs: [SceneNodeID],
        locationY: Double,
        rowHeight: Double = 22.0,
        metadata: ProductMetadata
    ) -> OutlinerDropDestination? {
        guard locationY.isFinite, rowHeight.isFinite, rowHeight > 0,
              metadata.sceneNodes[rowID] != nil,
              siblingIDs.contains(rowID) else {
            return nil
        }
        let siblings = siblingIDs
        guard let index = siblings.firstIndex(of: rowID) else {
            return nil
        }
        let upperBoundary = rowHeight / 3.0
        let lowerBoundary = rowHeight * 2.0 / 3.0
        if locationY < upperBoundary {
            return OutlinerDropDestination(
                parentID: parentID,
                beforeSiblingID: rowID
            )
        }
        if locationY > lowerBoundary {
            let nextIndex = siblings.index(after: index)
            let next = nextIndex < siblings.endIndex ? siblings[nextIndex] : nil
            return OutlinerDropDestination(
                parentID: parentID,
                beforeSiblingID: next
            )
        }
        return OutlinerDropDestination(parentID: rowID, beforeSiblingID: nil)
    }

    static func rootDropDestination() -> OutlinerDropDestination {
        OutlinerDropDestination(parentID: nil, beforeSiblingID: nil)
    }

    private struct OwnershipIndex {
        var generatedNodeIDs: Set<SceneNodeID> = []
        var patternRootIDs: Set<SceneNodeID> = []

        init(metadata: ProductMetadata) {
            var outputRoots: [SceneNodeID] = []
            var outputInstances: Set<ComponentInstanceID> = []
            for source in metadata.patternArrays.values {
                patternRootIDs.insert(source.rootSceneNodeID)
                outputRoots.append(contentsOf: source.outputSceneNodeIDs)
                outputInstances.formUnion(source.outputInstanceIDs)
            }
            for node in metadata.sceneNodes.values {
                let instanceID = node.reference?.componentInstanceID
                    ?? node.object?.componentInstanceID
                if let instanceID, outputInstances.contains(instanceID) {
                    outputRoots.append(node.id)
                }
            }
            var visited: Set<SceneNodeID> = []
            func mark(_ id: SceneNodeID) {
                guard visited.insert(id).inserted,
                      let node = metadata.sceneNodes[id] else { return }
                generatedNodeIDs.insert(id)
                for childID in node.childIDs {
                    mark(childID)
                }
            }
            for id in outputRoots {
                mark(id)
            }
        }
    }

    static func generatedOutputIDs(in metadata: ProductMetadata) -> Set<SceneNodeID> {
        OwnershipIndex(metadata: metadata).generatedNodeIDs
    }

    private static func kindTitle(for node: SceneNode) -> String {
        if let reference = node.reference {
            switch reference.kind {
            case .feature: return "Feature"
            case .body: return "Body"
            case .sketch: return "Sketch"
            case .componentInstance: return "Component Instance"
            case .construction: return "Construction"
            case .authoredMesh: return "Authored Mesh"
            }
        }
        return node.object?.category.title ?? "Scene Node"
    }

    private static func parentIDs(
        in metadata: ProductMetadata
    ) -> [SceneNodeID: SceneNodeID] {
        var result: [SceneNodeID: SceneNodeID] = [:]
        var visited: Set<SceneNodeID> = []
        func visit(_ id: SceneNodeID) {
            guard visited.insert(id).inserted,
                  let node = metadata.sceneNodes[id] else { return }
            for childID in node.childIDs {
                result[childID] = id
                visit(childID)
            }
        }
        for rootID in metadata.rootSceneNodeIDs {
            visit(rootID)
        }
        return result
    }
}
