import RupaCore
import Synchronization

/// What the overlay producer derives from one document alone, derived the first time a build asks
/// and shared by every later build of that document.
///
/// Parent frames and poly-spline patches are functions of the document, so builds that differ
/// only in selection or hover read what the document's first build derived instead of deriving it
/// again. The derivation runs in that first build, off the main actor. The viewport keeps one memo
/// per document identity (`ViewportDocumentOverlayMemoCache`); a memo never answers for another
/// document.
final class ViewportDocumentOverlayMemo: Sendable {
    /// The poly-spline patches and the admission their derivation charged, which a build that
    /// reuses them charges again: the derivation's work is shared, not its bounds.
    private struct PolySplinePatches: Sendable {
        let descriptors: [FeatureID: [ViewportPolySplinePatchDescriptor]]
        let positions: Int
        let visits: Int
    }

    let document: DesignDocument
    private let frames = Mutex<ViewportSceneNodeParentFrames?>(nil)
    private let patches = Mutex<PolySplinePatches?>(nil)

    init(document: DesignDocument) {
        self.document = document
    }

    /// The document's parent frames. A failed walk is thrown and not remembered.
    func parentFrames() throws -> ViewportSceneNodeParentFrames {
        if let built = frames.withLock({ $0 }) { return built }
        // Walked outside the lock; a concurrent first walk of the same document yields equal
        // frames, and the first stored one answers for both.
        let built = try ViewportSceneNodeParentFrames(document: document)
        return frames.withLock { stored in
            if let stored { return stored }
            stored = built
            return built
        }
    }

    /// The document's supported poly-spline patches, charging `checkpoint` as deriving them does.
    /// A derivation that throws is not remembered.
    func polySplinePatches(
        checkpoint: (Int, Int, Int) throws -> Void
    ) throws -> [FeatureID: [ViewportPolySplinePatchDescriptor]] {
        if let built = patches.withLock({ $0 }) {
            try checkpoint(0, built.positions, built.visits)
            return built.descriptors
        }
        var positions = 0
        var visits = 0
        let descriptors = try ViewportSpatialOverlayProducer.polySplinePatchDescriptors(document: document) {
            items, addedPositions, addedVisits in
            try checkpoint(items, addedPositions, addedVisits)
            positions += addedPositions
            visits += addedVisits
        }
        let built = PolySplinePatches(descriptors: descriptors, positions: positions, visits: visits)
        return patches.withLock { stored in
            if let stored { return stored.descriptors }
            stored = built
            return built.descriptors
        }
    }
}
