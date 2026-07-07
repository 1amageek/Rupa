import Foundation
import RupaCore
import RupaViewportScene

struct ViewportSceneSnapshotKey: Equatable {
    enum Source: Equatable {
        case document(DocumentGeneration)
        case dragPreview(UInt64)
    }

    var source: Source
    var currentEvaluationGeneration: DocumentGeneration?
    var evaluationCacheGeneration: DocumentGeneration?
    var renderInvalidation: RenderInvalidation
    var sectionClippingPlan: SectionAnalysisClippingPlan?
    var objectDefinitions: [ObjectTypeDefinition]
}

final class ViewportSceneSnapshotCache {
    private struct Entry {
        var key: ViewportSceneSnapshotKey
        var scene: ViewportScene
    }

    private var entries: [Entry] = []
    private let maximumEntryCount: Int

    init(maximumEntryCount: Int = 4) {
        self.maximumEntryCount = max(1, maximumEntryCount)
    }

    func scene(
        for key: ViewportSceneSnapshotKey?,
        build: () -> ViewportScene
    ) -> ViewportScene {
        guard let key else {
            return build()
        }
        if let index = entries.firstIndex(where: { $0.key == key }) {
            let entry = entries.remove(at: index)
            entries.insert(entry, at: 0)
            return entry.scene
        }

        let scene = build()
        entries.insert(Entry(key: key, scene: scene), at: 0)
        if entries.count > maximumEntryCount {
            entries.removeLast(entries.count - maximumEntryCount)
        }
        return scene
    }

    func invalidate() {
        entries.removeAll()
    }
}
