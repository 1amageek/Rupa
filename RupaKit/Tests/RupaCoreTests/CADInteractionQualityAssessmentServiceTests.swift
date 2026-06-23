import Testing
import RupaCore

@Test func cadInteractionQualityAssessmentCoversEveryGateForEachWorkflow() async throws {
    let result = CADInteractionQualityAssessmentService().assess()

    #expect(result.referenceDate == "2026-06-23")
    #expect(result.counts.entryCount == result.entries.count)
    #expect(result.entries.count >= 8)
    #expect(result.score > 0.0)
    #expect(result.score < 1.0)

    for entry in result.entries {
        #expect(entry.gateAssessments.map(\.gate) == CADInteractionQualityGate.allCases)
        #expect(entry.gateAssessments.allSatisfy { $0.rating != .missing })
        #expect(!entry.referenceSources.isEmpty)
        #expect(!entry.evidence.isEmpty)
        #expect(!entry.nextRequiredResult.isEmpty)
    }
}

@Test func cadInteractionQualityAssessmentRecordsDimensionDepthEdgeSupportAndOpenGaps() async throws {
    let result = CADInteractionQualityAssessmentService().assess()
    let dimension = try #require(result.entries.first { $0.area == .dimensions })

    #expect(dimension.workflow == "Dimension command target editing")
    #expect(dimension.referenceSources.contains("https://doc.plasticity.xyz/common/dimension"))
    #expect(dimension.currentRating == .partial)
    #expect(dimension.evidence.contains { evidence in
        evidence.notes.contains("Generated extrusion-depth edges resolve to object depth dimensions.")
    })
    #expect(dimension.openWork.contains("Solid face-distance pair dimensions."))
    #expect(!dimension.openWork.contains("Vertical/depth generated Edge dimensions."))
}

@Test func cadInteractionQualityAssessmentCountsBlockingGates() async throws {
    let result = CADInteractionQualityAssessmentService().assess()
    let countedBlockingGates = result.entries.reduce(0) { count, entry in
        count + entry.gateAssessments.filter { $0.rating.score < CADInteractionQualityRating.implemented.score }.count
    }

    #expect(result.counts.blockingGapCount == countedBlockingGates)
    #expect(result.counts.partialCount > 0)
    #expect(result.counts.implementedCount > 0)
}
