import RupaCore
import RupaCoreTypes

@MainActor
final class MeshSourcePresentationSectionGeometryCache {
    struct Key: Equatable {
        let presentationSnapshotID: EvaluationSnapshotID
        let sceneSnapshotKey: ViewportSceneSnapshotKey
        let plane: SectionAnalysisResult.Plane?
        let toleranceMeters: Double?
    }

    private var cachedKey: Key?
    private var cachedResolver: MeshSourcePresentationSectionGeometryResolver?
    private(set) var buildCount = 0

    func resolver(
        for key: Key?,
        build: () -> MeshSourcePresentationSectionGeometryResolver
    ) -> MeshSourcePresentationSectionGeometryResolver {
        guard let key else {
            buildCount += 1
            return build()
        }
        if cachedKey == key,
           let cachedResolver {
            return cachedResolver
        }
        let resolver = build()
        cachedKey = key
        cachedResolver = resolver
        buildCount += 1
        return resolver
    }

    func invalidate() {
        cachedKey = nil
        cachedResolver = nil
    }
}
