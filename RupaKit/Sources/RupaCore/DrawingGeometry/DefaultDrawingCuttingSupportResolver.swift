import SwiftCAD
import RupaCoreTypes

/// Retains original local cutting planes and ordered source hierarchy factors.
public struct DefaultDrawingCuttingSupportResolver: DrawingCuttingSupportResolving {
    public init() {}

    // FIXME(INCOMPLETE_IMPLEMENTATION): This production source resolver preserves
    // original plane/word authority and charges factor preparation/output on the
    // caller ledger. Whole hierarchy expansion allocation needs the same caller
    // callback before full bounded selected-section composition is complete.
    public func supports(document: DesignDocument, savedView: SavedView, maximumOccurrences: Int,
                         maximumSupports: Int, usage: inout DrawingExchangeUsage) throws -> [BRepDrawingCuttingSupport] {
        try usage.check()
        guard maximumOccurrences > 0, maximumSupports > 0,
              document.productMetadata.savedViews[savedView.id] == savedView else {
            throw EditorError(code: .referenceUnresolved, message: "Original cutting support requires the current saved view and positive capacities.")
        }
        try savedView.validate(sceneNodes: document.productMetadata.sceneNodes,
            constructionPlanes: document.productMetadata.constructionPlanes)
        let selected = Set(savedView.sectionState.sectionSceneNodeIDs)
        guard selected.count == savedView.sectionState.sectionSceneNodeIDs.count else {
            throw EditorError(code: .commandInvalid, message: "Selected original section sources are duplicated.")
        }
        let occurrences = try SceneNodeHierarchy(metadata: document.productMetadata).resolvedOriginalOccurrences()
        guard occurrences.count <= maximumOccurrences else {
            throw EditorError(code: .commandInvalid, message: "Original cutting occurrence capacity is exhausted.")
        }
        var found: Set<SceneNodeID> = []
        var result: [BRepDrawingCuttingSupport] = []
        for occurrence in occurrences {
            try usage.charge(work: 1)
            guard selected.contains(occurrence.sourceSceneNodeID) else { continue }
            guard let node = document.productMetadata.sceneNodes[occurrence.sourceSceneNodeID],
                  node.reference?.kind == .construction || node.object?.category == .construction else {
                throw EditorError(code: .referenceUnresolved, message: "Selected original cutting source is not a construction plane.")
            }
            found.insert(node.id)
            let original: SketchPlane
            if let id = node.reference?.constructionPlaneID {
                guard let source = document.productMetadata.constructionPlanes[id] else {
                    throw EditorError(code: .referenceUnresolved, message: "Selected original construction plane source is absent.")
                }
                original = source.plane
            } else { original = .xy }
            let plane: Plane3D
            switch original {
            case .xy: plane = .init(origin: .origin, normal: .unitZ, uDirection: .unitX)
            case .yz: plane = .init(origin: .origin, normal: .unitX, uDirection: .unitY)
            case .zx: plane = .init(origin: .origin, normal: .unitY, uDirection: .unitZ)
            case .plane(let value): plane = value
            }
            guard result.count < maximumSupports else {
                throw EditorError(code: .commandInvalid, message: "Original cutting support capacity is exhausted.")
            }
            let word = try DrawingOriginalPlacementWordBuilder().word(from: occurrence, usage: &usage)
            let identity = occurrence.id.description
            let storage = identity.utf8.count.addingReportingOverflow(MemoryLayout<BRepDrawingCuttingSupport>.stride)
            guard !storage.overflow else { throw EditorError(code: .commandInvalid, message: "Original cutting identity storage overflowed.") }
            try usage.charge(entities: 1, work: 1, bytes: storage.partialValue)
            result.append(.init(originalPlane: plane, operationWord: word, sourceIdentity: identity))
        }
        guard found == selected else {
            throw EditorError(code: .referenceUnresolved, message: "Selected original cutting source has no complete scene occurrence.")
        }
        return result
    }
}
