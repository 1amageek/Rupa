import RupaCore
import Testing
@testable import RupaUI

@MainActor
@Test func patternArraySummaryCacheReusesResultForStableGenerationAndDirtyState() {
    var buildCount = 0
    let cache = PatternArraySummaryCache { _, generation, dirty in
        buildCount += 1
        return PatternArraySummaryResult(
            generation: generation,
            dirty: dirty,
            patternArrays: []
        )
    }
    let document = DesignDocument.empty()

    let first = cache.result(
        document: document,
        generation: DocumentGeneration(1),
        dirty: false
    )
    let second = cache.result(
        document: document,
        generation: DocumentGeneration(1),
        dirty: false
    )
    let third = cache.result(
        document: document,
        generation: DocumentGeneration(2),
        dirty: false
    )
    let fourth = cache.result(
        document: document,
        generation: DocumentGeneration(2),
        dirty: true
    )

    #expect(first.generation == DocumentGeneration(1))
    #expect(second.generation == DocumentGeneration(1))
    #expect(third.generation == DocumentGeneration(2))
    #expect(fourth.dirty)
    #expect(buildCount == 3)
}

@MainActor
@Test func patternArraySummaryCacheCanBeInvalidated() {
    var buildCount = 0
    let cache = PatternArraySummaryCache { _, generation, dirty in
        buildCount += 1
        return PatternArraySummaryResult(
            generation: generation,
            dirty: dirty,
            patternArrays: []
        )
    }
    let document = DesignDocument.empty()

    _ = cache.result(
        document: document,
        generation: DocumentGeneration(1),
        dirty: false
    )
    cache.invalidate()
    _ = cache.result(
        document: document,
        generation: DocumentGeneration(1),
        dirty: false
    )

    #expect(buildCount == 2)
}
