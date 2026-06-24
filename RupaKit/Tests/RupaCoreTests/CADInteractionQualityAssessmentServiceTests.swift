import Testing
import RupaCore

@Test func cadInteractionQualityAssessmentCoversEveryGateForEachWorkflow() async throws {
    let result = CADInteractionQualityAssessmentService().assess()

    #expect(result.referenceDate == "2026-06-24")
    #expect(result.counts.entryCount == result.entries.count)
    #expect(result.entries.count >= 14)
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

@Test func cadInteractionQualityAssessmentCoversPlasticityProductParityAreasAsEntries() async throws {
    let result = CADInteractionQualityAssessmentService().assess()
    let requiredAreas: [CADInteractionQualityArea] = [
        .filletingAndBlending,
        .booleanModeling,
        .directModeling,
        .exchangeAndDrawings,
        .patternsAndArrays,
        .sectionAnalysis,
    ]

    for area in requiredAreas {
        let entry = try #require(result.entries.first { $0.area == area })

        #expect(entry.currentRating != .missing)
        #expect(entry.gateAssessments.map(\.gate) == CADInteractionQualityGate.allCases)
        #expect(entry.gateAssessments.allSatisfy { $0.rating != .missing })
        #expect(!entry.referenceSources.isEmpty)
        #expect(!entry.evidence.isEmpty)
        #expect(!entry.openWork.isEmpty)
        #expect(!entry.nextRequiredResult.isEmpty)
    }

    let filleting = try #require(result.entries.first { $0.area == .filletingAndBlending })
    #expect(filleting.currentRating == .partial)
    #expect(filleting.referenceSources.contains("https://doc.plasticity.xyz/solid/fillet-shell"))
    #expect(filleting.openWork.contains { $0.contains("G2") && $0.contains("variable-radius") })
    #expect(filleting.evidence.contains { evidence in
        evidence.notes.contains("The current fillet command does not yet expose shell-grade conic, G2, constant-width, variable-radius, or range-limited blend contracts.")
    })

    let booleans = try #require(result.entries.first { $0.area == .booleanModeling })
    #expect(booleans.currentRating == .partial)
    #expect(booleans.referenceSources.contains("https://doc.plasticity.xyz/solid/boolean"))
    #expect(booleans.openWork.contains("Standalone Boolean command with target/tool selection contracts."))
    #expect(booleans.evidence.contains { evidence in
        evidence.notes.contains("Standalone Boolean target/tool workflows and mixed Solid/Sheet operations remain gap items.")
    })

    let directModeling = try #require(result.entries.first { $0.area == .directModeling })
    #expect(directModeling.currentRating == .partial)
    #expect(directModeling.referenceSources.contains("https://doc.plasticity.xyz/solid/offset-face"))
    #expect(directModeling.openWork.contains { $0.contains("Delete Face") && $0.contains("Draft Face") })

    let exchange = try #require(result.entries.first { $0.area == .exchangeAndDrawings })
    #expect(exchange.currentRating == .partial)
    #expect(exchange.referenceSources.contains("https://doc.plasticity.xyz/plasticity-essentials/export-hidden-line"))
    #expect(exchange.openWork.contains { $0.contains("Hidden-line export") })

    let arrays = try #require(result.entries.first { $0.area == .patternsAndArrays })
    let arrayCommandRating = try gateRating(.commandContract, in: arrays)
    #expect(arrays.currentRating == .planned)
    #expect(arrayCommandRating == .planned)
    #expect(arrays.referenceSources.contains("https://doc.plasticity.xyz/common/rectangular-array"))
    #expect(arrays.openWork.contains { $0.contains("Rectangular array") })

    let section = try #require(result.entries.first { $0.area == .sectionAnalysis })
    #expect(section.currentRating == .partial)
    #expect(section.referenceSources.contains("https://doc.plasticity.xyz/common/section-analysis"))
    #expect(section.openWork.contains { $0.contains("Virtual section clipping") })
}

@Test func cadInteractionQualityAssessmentRecordsSelectionDimensionFacePairSupportAndOpenGaps() async throws {
    let result = CADInteractionQualityAssessmentService().assess()
    let dimension = try #require(result.entries.first { $0.area == .dimensions })

    #expect(dimension.workflow == "Dimension command target editing")
    #expect(dimension.referenceSources.contains("https://doc.plasticity.xyz/common/dimension"))
    #expect(dimension.currentRating == .partial)
    #expect(dimension.evidence.contains { evidence in
        evidence.notes.contains("Generated extrusion-depth edges resolve to object depth dimensions.")
    })
    #expect(dimension.evidence.contains { evidence in
        evidence.notes.contains("Generated solid face pairs resolve to SwiftCAD selection dimensions and evaluate through the shared CAD kernel.")
    })
    #expect(!dimension.openWork.contains("Solid face-distance pair dimensions."))
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

private func gateRating(
    _ gate: CADInteractionQualityGate,
    in entry: CADInteractionQualityAssessmentEntry
) throws -> CADInteractionQualityRating {
    let assessment = try #require(entry.gateAssessments.first { $0.gate == gate })
    return assessment.rating
}
