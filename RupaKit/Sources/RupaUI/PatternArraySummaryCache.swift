import RupaCore

@MainActor
final class PatternArraySummaryCache {
    typealias SummaryBuilder = @MainActor (
        DesignDocument,
        DocumentGeneration,
        Bool
    ) -> PatternArraySummaryResult

    private struct CacheKey: Equatable {
        var generation: DocumentGeneration
        var dirty: Bool
    }

    private let summaryBuilder: SummaryBuilder
    private var cachedKey: CacheKey?
    private var cachedResult: PatternArraySummaryResult?

    init(
        summaryBuilder: @escaping SummaryBuilder = { document, generation, dirty in
            PatternArraySummaryService().summarize(
                document: document,
                generation: generation,
                dirty: dirty
            )
        }
    ) {
        self.summaryBuilder = summaryBuilder
    }

    func result(
        document: DesignDocument,
        generation: DocumentGeneration,
        dirty: Bool
    ) -> PatternArraySummaryResult {
        let key = CacheKey(generation: generation, dirty: dirty)
        if cachedKey == key,
           let cachedResult {
            return cachedResult
        }
        let result = summaryBuilder(document, generation, dirty)
        cachedKey = key
        cachedResult = result
        return result
    }

    func invalidate() {
        cachedKey = nil
        cachedResult = nil
    }
}
