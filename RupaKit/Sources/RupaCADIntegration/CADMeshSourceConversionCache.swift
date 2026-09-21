import RupaCoreTypes
import Synchronization

/// Retains pure conversion results, never transaction revisions or CAD state.
package final class CADMeshSourceConversionCache: Sendable {
    package typealias Entries = [GeometrySourceID: CADDocumentEvaluationCache.CachedMeshSource]
    private let state = Mutex<Entries>([:])

    package init() {}

    package func snapshot() -> Entries {
        state.withLock { $0 }
    }

    package func replace(with entries: Entries) {
        let previous = state.withLock { current in
            let previous = current
            current = entries
            return previous
        }
        withExtendedLifetime(previous) {}
    }
}
