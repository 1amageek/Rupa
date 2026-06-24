import Testing
import RupaCore

@Test func cadInteractionQualityAssessmentCoversEveryGateForEachWorkflow() async throws {
    let result = CADInteractionQualityAssessmentService().assess()

    #expect(result.referenceDate == "2026-06-24")
    #expect(result.counts.entryCount == result.entries.count)
    #expect(Set(result.entries.map(\.area)) == Set(CADInteractionQualityArea.allCases))
    #expect(result.entries.map(\.area).count == Set(result.entries.map(\.area)).count)
    #expect(result.score > 0.0)
    #expect(result.score < 1.0)

    for entry in result.entries {
        #expect(entry.gateAssessments.map(\.gate) == CADInteractionQualityGate.allCases)
        #expect(!entry.referenceSources.isEmpty)
        #expect(!entry.evidence.isEmpty)
        #expect(!entry.nextRequiredResult.isEmpty)
        for assessment in entry.gateAssessments where assessment.rating == .missing {
            #expect(!assessment.openWork.isEmpty)
        }
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
        for assessment in entry.gateAssessments where assessment.rating == .missing {
            #expect(!assessment.openWork.isEmpty)
        }
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
    let arrayInspectorRating = try gateRating(.inspectorAffordance, in: arrays)
    let arrayAgentRating = try gateRating(.agentParity, in: arrays)
    let arrayDiagnosticsRating = try gateRating(.measurementDiagnostics, in: arrays)
    #expect(arrays.currentRating == .partial)
    #expect(arrayCommandRating == .partial)
    #expect(arrayInspectorRating == .partial)
    #expect(arrayAgentRating == .implemented)
    #expect(arrayDiagnosticsRating == .partial)
    #expect(arrays.referenceSources.contains("https://doc.plasticity.xyz/common/rectangular-array"))
    #expect(!arrays.openWork.contains { $0.contains("radial array center") })
    #expect(!arrays.openWork.contains { $0.contains("viewport curve array path pick mode") })
    #expect(arrays.openWork.contains { $0.contains("Viewport preview affordances") })
    #expect(arrays.evidence.contains { evidence in
        evidence.sourceFiles.contains("RupaKit/Sources/RupaCore/PatternArraySource.swift")
    })
    #expect(arrays.evidence.contains { evidence in
        evidence.sourceFiles.contains("RupaKit/Sources/RupaCore/PatternArraySummaryService.swift")
    })
    #expect(arrays.evidence.contains { evidence in
        evidence.sourceFiles.contains("RupaKit/Sources/RupaUI/PatternArrayInspectorState.swift")
    })
    #expect(arrays.evidence.contains { evidence in
        evidence.sourceFiles.contains("RupaKit/Sources/RupaUI/PatternArrayEditingService.swift")
    })
    #expect(arrays.evidence.contains { evidence in
        evidence.sourceFiles.contains("RupaKit/Sources/RupaUI/PatternArrayCurvePathPickService.swift")
    })
    #expect(arrays.evidence.contains { evidence in
        evidence.notes.contains("Pattern Array summaries expose editable fields, lifecycle actions, source-owned output edit policy, output IDs, and diagnostics without forcing CAD evaluation.")
    })
    #expect(arrays.evidence.contains { evidence in
        evidence.notes.contains("Design display snapshots keep invalid PatternArraySource records discoverable with diagnostics instead of dropping sources whose definition, root scene node, or generated outputs are missing.")
    })
    #expect(arrays.evidence.contains { evidence in
        evidence.notes.contains("Pattern Array summary diagnostics mirror source-owned output invariants for missing instances, mismatched transforms, duplicate ownership, root child mapping, and independent-copy feature closure checks.")
    })
    #expect(arrays.evidence.contains { evidence in
        evidence.notes.contains("The object Inspector now maps selected source roots, generated outputs, and independent-copy descendants back to their PatternArraySource and displays ownership, lifecycle actions, output mode, selected output index, and diagnostics.")
    })
    #expect(arrays.evidence.contains { evidence in
        evidence.notes.contains("The Pattern Array Inspector exposes source-owned output mode plus rectangular first- and second-axis controls, radial center, axis, angular spacing or extent, radial repetition, and curve count, twist, scale, alignment, and extent controls that update the PatternArraySource instead of generated outputs.")
    })
    #expect(arrays.evidence.contains { evidence in
        evidence.notes.contains("The Pattern Array Inspector starts a dedicated viewport Curve Array path pick mode; viewport sketch line, circle, arc, or spline targets update the PatternArraySource path without replacing the active Pattern Array selection.")
    })
    #expect(arrays.evidence.contains { evidence in
        evidence.notes.contains("Curve Array ratio extent editing clamps UI and service inputs to the Core planner range before source-owned regeneration.")
    })

    let section = try #require(result.entries.first { $0.area == .sectionAnalysis })
    #expect(section.currentRating == .partial)
    #expect(section.referenceSources.contains("https://doc.plasticity.xyz/common/section-analysis"))
    #expect(section.openWork.contains { $0.contains("Virtual section clipping") })

    let sketchPrecision = try #require(result.entries.first { $0.area == .sketchPrecision })
    #expect(sketchPrecision.currentRating == .partial)
    #expect(sketchPrecision.referenceSources.contains("https://doc.plasticity.xyz/sketch"))
    #expect(sketchPrecision.openWork.contains { $0.contains("General sketch solver") })

    let performance = try #require(result.entries.first { $0.area == .performance })
    #expect(performance.currentRating == .partial)
    #expect(performance.referenceSources.contains("Rupa/CAD_QUALITY_MILESTONES.md"))
    #expect(performance.evidence.contains { evidence in
        evidence.notes.contains("Viewport scene construction, Inspector shape and surface panels, Agent display/mesh/topology/surface summaries, measurement, surface frame, and selection dimension read paths can consume a store-validated current evaluation context instead of forcing another CAD evaluation.")
    })
    #expect(performance.evidence.contains { evidence in
        evidence.notes.contains("Evaluation context reuse now checks both document generation and CAD source fingerprint before returning an evaluated document.")
    })
    #expect(performance.evidence.contains { evidence in
        evidence.sourceFiles.contains("RupaKit/Sources/RupaCore/DocumentEvaluationContext.swift")
    })
    #expect(!performance.openWork.contains { $0.contains("Agent summaries for current evaluation cache reuse") })
    #expect(performance.openWork.contains { $0.contains("memory pressure") })
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
