import Testing
import RupaCore

@Test func cadInteractionQualityAssessmentCoversEveryGateForEachWorkflow() async throws {
    let result = CADInteractionQualityAssessmentService().assess()

    #expect(result.referenceDate == "2026-07-03")
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
    #expect(!booleans.openWork.contains("Standalone Boolean command with target/tool selection contracts."))
    #expect(booleans.openWork.contains { $0.contains("general non-orthogonal Solid and Sheet topology") })
    #expect(booleans.evidence.contains { evidence in
        evidence.notes.contains("Standalone Boolean features now own target body references, one tool body reference, operation, and keep-tools policy in source data.")
    })
    #expect(booleans.evidence.contains { evidence in
        evidence.notes.contains("SwiftCAD can extract occupied cells from supported orthogonal solid operands, so previous connected orthogonal cell-union Boolean results can become follow-on Boolean targets.")
    })
    #expect(booleans.evidence.contains { evidence in
        evidence.tests.contains("RupaKit/Tests/RupaCoreTests/BooleanCommandTests.swift")
    })

    let directModeling = try #require(result.entries.first { $0.area == .directModeling })
    #expect(directModeling.currentRating == .partial)
    #expect(directModeling.referenceSources.contains("https://doc.plasticity.xyz/solid/offset-face"))
    #expect(directModeling.openWork.contains { $0.contains("Healing Delete Face") && $0.contains("refill") })
    #expect(directModeling.openWork.contains { $0.contains("Match Face") && $0.contains("Draft Face") })
    #expect(directModeling.evidence.contains { evidence in
        evidence.sourceFiles.contains("RupaKit/Sources/RupaCore/DesignDocument+SolidFaceDelete.swift")
    })
    #expect(directModeling.evidence.contains { evidence in
        evidence.notes.contains("Healing Delete Face that refills, extends, or shrinks adjacent faces is not yet implemented; current Delete Face intentionally preserves an open sheet body result for the supported non-healing subset.")
    })
    #expect(directModeling.evidence.contains { evidence in
        evidence.notes.contains("Workspace Inspector exposes non-healing Delete Face for selected generated face targets and routes it through the same Core command used by Automation and Agent.")
    })

    let exchange = try #require(result.entries.first { $0.area == .exchangeAndDrawings })
    #expect(exchange.currentRating == .partial)
    #expect(exchange.referenceSources.contains("https://doc.plasticity.xyz/plasticity-essentials/export-hidden-line"))
    #expect(exchange.openWork.contains { $0.contains("Hidden-line export") })

    let arrays = try #require(result.entries.first { $0.area == .patternsAndArrays })
    let arrayCommandRating = try gateRating(.commandContract, in: arrays)
    let arrayViewportRating = try gateRating(.viewportAffordance, in: arrays)
    let arrayInspectorRating = try gateRating(.inspectorAffordance, in: arrays)
    let arrayAgentRating = try gateRating(.agentParity, in: arrays)
    let arrayDiagnosticsRating = try gateRating(.measurementDiagnostics, in: arrays)
    #expect(arrays.currentRating == .partial)
    #expect(arrayCommandRating == .partial)
    #expect(arrayViewportRating == .partial)
    #expect(arrayInspectorRating == .partial)
    #expect(arrayAgentRating == .implemented)
    #expect(arrayDiagnosticsRating == .partial)
    #expect(arrays.referenceSources.contains("https://doc.plasticity.xyz/common/rectangular-array"))
    #expect(!arrays.openWork.contains { $0.contains("radial array center") })
    #expect(!arrays.openWork.contains { $0.contains("viewport curve array path pick mode") })
    #expect(!arrays.openWork.contains { $0.contains("curve count/extent/path") })
    #expect(!arrays.openWork.contains { $0.contains("curve count/path") })
    #expect(!arrays.openWork.contains { $0.contains("extent-density count editing") })
    #expect(!arrays.openWork.contains { $0.contains("curve-path replacement previews") })
    #expect(!arrays.openWork.contains { $0.contains("Direct viewport curve-path edit handles") })
    #expect(arrays.openWork.contains { $0.contains("independent-copy") })
    #expect(arrays.evidence.contains { evidence in
        evidence.sourceFiles.contains("RupaKit/Sources/RupaCore/PatternArraySource.swift")
    })
    #expect(arrays.evidence.contains { evidence in
        evidence.sourceFiles.contains("RupaKit/Sources/RupaCore/PatternArraySummaryService.swift")
    })
    #expect(arrays.evidence.contains { evidence in
        evidence.sourceFiles.contains("RupaKit/Sources/RupaCore/PatternArrayDistancePolicy.swift")
    })
    #expect(arrays.evidence.contains { evidence in
        evidence.sourceFiles.contains("RupaKit/Sources/RupaCore/PatternArrayAnglePolicy.swift")
    })
    #expect(arrays.evidence.contains { evidence in
        evidence.sourceFiles.contains("RupaKit/Sources/RupaCore/PatternArrayExpressionResolver.swift")
    })
    #expect(arrays.evidence.contains { evidence in
        evidence.sourceFiles.contains("RupaKit/Sources/RupaCore/PatternArrayCurvePathGeometryService.swift")
    })
    #expect(arrays.evidence.contains { evidence in
        evidence.sourceFiles.contains("RupaKit/Sources/RupaCore/PatternArrayIndependentCopyBuilder.swift")
    })
    #expect(arrays.evidence.contains { evidence in
        evidence.sourceFiles.contains("RupaKit/Sources/RupaCore/DesignDocument+PatternArray.swift")
    })
    #expect(arrays.evidence.contains { evidence in
        evidence.sourceFiles.contains("RupaKit/Sources/RupaCore/PatternArrayDocumentSynchronizer.swift")
    })
    #expect(arrays.evidence.contains { evidence in
        evidence.sourceFiles.contains("RupaKit/Sources/RupaCore/PatternArrayOwnershipResolver.swift")
    })
    #expect(arrays.evidence.contains { evidence in
        evidence.sourceFiles.contains("RupaKit/Sources/RupaAutomation/AutomationCommand.swift")
    })
    #expect(arrays.evidence.contains { evidence in
        evidence.sourceFiles.contains("RupaKit/Sources/RupaAutomation/AutomationRunner.swift")
    })
    #expect(arrays.evidence.contains { evidence in
        evidence.sourceFiles.contains("RupaKit/Sources/RupaAgentRuntime/AgentCommandController.swift")
    })
    #expect(arrays.evidence.contains { evidence in
        evidence.sourceFiles.contains("RupaKit/Sources/RupaUI/PatternArrayInspectorState.swift")
    })
    #expect(arrays.evidence.contains { evidence in
        evidence.sourceFiles.contains("RupaKit/Sources/RupaUI/PatternArrayEditingService.swift")
    })
    #expect(arrays.evidence.contains { evidence in
        evidence.sourceFiles.contains("RupaKit/Sources/RupaUI/PatternArrayExpressionWritebackService.swift")
    })
    #expect(arrays.evidence.contains { evidence in
        evidence.sourceFiles.contains("RupaKit/Sources/RupaUI/PatternArrayCurvePathPickService.swift")
    })
    #expect(arrays.evidence.contains { evidence in
        evidence.sourceFiles.contains("RupaKit/Sources/RupaUI/PatternArraySummaryCache.swift")
    })
    #expect(arrays.evidence.contains { evidence in
        evidence.sourceFiles.contains("RupaKit/Sources/RupaRendering/ViewportPatternArrayPreviewService.swift")
    })
    #expect(arrays.evidence.contains { evidence in
        evidence.sourceFiles.contains("RupaKit/Sources/RupaRendering/ViewportPatternArrayLinearAxisAffordanceService.swift")
    })
    #expect(arrays.evidence.contains { evidence in
        evidence.sourceFiles.contains("RupaKit/Sources/RupaRendering/ViewportIndependentCopyExtrudeDistanceAffordanceService.swift")
    })
    #expect(arrays.evidence.contains { evidence in
        evidence.sourceFiles.contains("RupaKit/Sources/RupaRendering/ViewportIndependentCopyOutputSelectionIndex.swift")
    })
    #expect(arrays.evidence.contains { evidence in
        evidence.sourceFiles.contains("RupaKit/Sources/RupaRendering/ViewportIndependentCopyBodyDimensionDragTarget.swift")
    })
    #expect(arrays.evidence.contains { evidence in
        evidence.sourceFiles.contains("RupaKit/Sources/RupaRendering/ViewportIndependentCopyBodyDimensionAffordanceService.swift")
    })
    #expect(arrays.evidence.contains { evidence in
        evidence.sourceFiles.contains("RupaKit/Sources/RupaRendering/ViewportPatternArraySourceSelectionIndex.swift")
    })
    #expect(arrays.evidence.contains { evidence in
        evidence.sourceFiles.contains("RupaKit/Sources/RupaRendering/ViewportTransformUtilities.swift")
    })
    #expect(arrays.evidence.contains { evidence in
        evidence.sourceFiles.contains("RupaKit/Sources/RupaRendering/ViewportPatternArrayRadialAngleAffordanceService.swift")
    })
    #expect(arrays.evidence.contains { evidence in
        evidence.sourceFiles.contains("RupaKit/Sources/RupaRendering/ViewportPatternArrayCurveExtentAffordanceService.swift")
    })
    #expect(arrays.evidence.contains { evidence in
        evidence.sourceFiles.contains("RupaKit/Sources/RupaRendering/ViewportPatternArrayCurvePathPointDragTarget.swift")
    })
    #expect(arrays.evidence.contains { evidence in
        evidence.sourceFiles.contains("RupaKit/Sources/RupaRendering/ViewportPatternArrayCurvePathPointAffordanceService.swift")
    })
    #expect(arrays.evidence.contains { evidence in
        evidence.sourceFiles.contains("RupaKit/Sources/RupaRendering/ViewportPatternArrayOutputModeTarget.swift")
    })
    #expect(arrays.evidence.contains { evidence in
        evidence.sourceFiles.contains("RupaKit/Sources/RupaRendering/ViewportPatternArrayOutputModeAffordanceService.swift")
    })
    #expect(arrays.evidence.contains { evidence in
        evidence.sourceFiles.contains("RupaKit/Sources/RupaRendering/ViewportPatternArrayCurvePathReplacementPreviewRequest.swift")
    })
    #expect(arrays.evidence.contains { evidence in
        evidence.sourceFiles.contains("RupaKit/Sources/RupaRendering/ViewportPatternArrayCurvePathReplacementPreviewService.swift")
    })
    #expect(arrays.evidence.contains { evidence in
        evidence.tests.contains("RupaKit/Tests/RupaRenderingTests/ViewportPatternArrayPreviewServiceTests.swift")
    })
    #expect(arrays.evidence.contains { evidence in
        evidence.tests.contains("RupaKit/Tests/RupaRenderingTests/ViewportPatternArrayLinearAxisAffordanceServiceTests.swift")
    })
    #expect(arrays.evidence.contains { evidence in
        evidence.tests.contains("RupaKit/Tests/RupaRenderingTests/ViewportIndependentCopyExtrudeDistanceAffordanceServiceTests.swift")
    })
    #expect(arrays.evidence.contains { evidence in
        evidence.tests.contains("RupaKit/Tests/RupaRenderingTests/ViewportIndependentCopyBodyDimensionAffordanceServiceTests.swift")
    })
    #expect(arrays.evidence.contains { evidence in
        evidence.tests.contains("RupaKit/Tests/RupaRenderingTests/ViewportPatternArrayRadialAngleAffordanceServiceTests.swift")
    })
    #expect(arrays.evidence.contains { evidence in
        evidence.tests.contains("RupaKit/Tests/RupaRenderingTests/ViewportPatternArrayCopyCountAffordanceServiceTests.swift")
    })
    #expect(arrays.evidence.contains { evidence in
        evidence.tests.contains("RupaKit/Tests/RupaCoreTests/PatternArrayExpressionResolverTests.swift")
    })
    #expect(arrays.evidence.contains { evidence in
        evidence.tests.contains("RupaKit/Tests/RupaCoreTests/PatternArrayCurvePathGeometryServiceTests.swift")
    })
    #expect(arrays.evidence.contains { evidence in
        evidence.tests.contains("RupaKit/Tests/RupaCoreTests/PatternArrayOwnershipResolverTests.swift")
    })
    #expect(arrays.evidence.contains { evidence in
        evidence.tests.contains("RupaKit/Tests/RupaRenderingTests/ViewportPatternArrayCurveExtentAffordanceServiceTests.swift")
    })
    #expect(arrays.evidence.contains { evidence in
        evidence.tests.contains("RupaKit/Tests/RupaRenderingTests/ViewportPatternArrayCurvePathPointAffordanceServiceTests.swift")
    })
    #expect(arrays.evidence.contains { evidence in
        evidence.tests.contains("RupaKit/Tests/RupaRenderingTests/ViewportPatternArrayOutputModeAffordanceServiceTests.swift")
    })
    #expect(arrays.evidence.contains { evidence in
        evidence.tests.contains("RupaKit/Tests/RupaRenderingTests/ViewportPatternArrayCurvePathReplacementPreviewServiceTests.swift")
    })
    #expect(arrays.evidence.contains { evidence in
        evidence.tests.contains("RupaKit/Tests/RupaAutomationTests/AutomationRunnerTests.swift")
    })
    #expect(arrays.evidence.contains { evidence in
        evidence.tests.contains("RupaKit/Tests/RupaAgentTests/AgentCommandControllerTests.swift")
    })
    #expect(arrays.evidence.contains { evidence in
        evidence.notes.contains("Pattern Array summaries expose editable fields, lifecycle actions, source-owned scene output policy, cloned feature edit policy, output IDs, independent-copy generation definition identity, per-output source-divergence state, regeneration policy, and diagnostics without forcing CAD evaluation.")
    })
    #expect(arrays.evidence.contains { evidence in
        evidence.notes.contains("Design display snapshots keep invalid PatternArraySource records discoverable with diagnostics instead of dropping sources whose definition, root scene node, or generated outputs are missing.")
    })
    #expect(arrays.evidence.contains { evidence in
        evidence.notes.contains("Pattern Array summary diagnostics mirror source-owned output invariants for missing instances, mismatched transforms, duplicate ownership, root child mapping, independent-copy feature closure checks, stale independent-copy definition identity, and downstream feature dependents that block output removal.")
    })
    #expect(arrays.evidence.contains { evidence in
        evidence.notes.contains("Pattern Array command mutation delegates output regeneration to a dedicated Core synchronizer and source-owned output lookup to a dedicated ownership resolver.")
    })
    #expect(arrays.evidence.contains { evidence in
        evidence.notes.contains("Independent-copy Pattern Array regeneration persists a SHA-256 ComponentDefinition identity over scene roots plus remapped feature operation payloads, reuses overlapping output scene roots only while that identity remains unchanged, and rebuilds output features when the source definition identity changes.")
    })
    #expect(arrays.evidence.contains { evidence in
        evidence.notes.contains("The object Inspector now maps selected source roots, generated outputs, and independent-copy descendants back to their PatternArraySource and displays ownership, lifecycle actions, output mode, selected output index, cloned feature edit policy, independent-copy source-divergence state, regeneration policy, and diagnostics.")
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
    #expect(arrays.evidence.contains { evidence in
        evidence.notes.contains("The Pattern Array Inspector reuses generation-keyed summary results so SwiftUI redraws do not repeatedly run transform planning or sketch curve extraction for unchanged documents.")
    })
    #expect(arrays.evidence.contains { evidence in
        evidence.notes.contains("The viewport resolves selected PatternArraySource roots, component-instance outputs, and independent-copy descendants into source-owned output outlines, copy markers, and count labels without scanning global component-instance references.")
    })
    #expect(arrays.evidence.contains { evidence in
        evidence.notes.contains("The viewport exposes rectangular Pattern Array first- and second-axis distance handles that resolve selected source roots or outputs back to PatternArraySource IDs and commit source-owned distance updates after drag completion.")
    })
    #expect(arrays.evidence.contains { evidence in
        evidence.notes.contains("The viewport exposes independent-copy cloned extrude distance handles that resolve selected output roots or descendants to clone feature IDs, derive normal directions from profile sketch planes, and commit cloned-feature distance edits after drag completion.")
    })
    #expect(arrays.evidence.contains { evidence in
        evidence.notes.contains("The viewport exposes independent-copy cloned box X/Z and cylinder radius handles that share the independent-copy output selection index, read current object dimensions, and commit direct cloned-feature body dimension edits after drag completion.")
    })
    #expect(arrays.evidence.contains { evidence in
        evidence.notes.contains("The viewport exposes radial Pattern Array angular spacing/extent handles and radial-axis distance handles through the shared PatternArray source-selection index.")
    })
    #expect(arrays.evidence.contains { evidence in
        evidence.notes.contains("The viewport exposes Pattern Array copy-count handles for rectangular axes, radial angular/radial axes, extent-density modes, and Curve Pattern Array density counts while preserving distance, angle, path extent, and source-owned output regeneration semantics.")
    })
    #expect(arrays.evidence.contains { evidence in
        evidence.notes.contains("The viewport exposes Curve Pattern Array extent handles that use the shared Core curve-path geometry resolver so viewport dragging and generated copy placement agree on path length and sampling.")
    })
    #expect(arrays.evidence.contains { evidence in
        evidence.notes.contains("The viewport exposes direct Curve Pattern Array polyline path-point handles that commit source-owned path point edits without mutating sketch-entity paths.")
    })
    #expect(arrays.evidence.contains { evidence in
        evidence.notes.contains("The viewport exposes Pattern Array output-mode badges that resolve selected source roots, generated outputs, and independent-copy descendants back to source-owned output mode regeneration.")
    })
    #expect(arrays.evidence.contains { evidence in
        evidence.notes.contains("The viewport previews Curve Pattern Array path replacement candidates with planner-derived ghost output markers before committing the pick-mode source update.")
    })
    #expect(arrays.evidence.contains { evidence in
        evidence.notes.contains("Viewport and inspector Pattern Array edits preserve direct parameter references by updating referenced ParameterTable values when quantity kinds match.")
    })
    #expect(arrays.evidence.contains { evidence in
        evidence.notes.contains("Pattern Array generation, curve path extent resolution, and viewport affordance placement share the same parameter-aware expression resolver so Agent-authored parametric arrays remain directly editable in the UI.")
    })
    #expect(arrays.evidence.contains { evidence in
        evidence.notes.contains("Agent and Automation can update independent-copy cloned extrude distances plus rectangular-box and cylinder dimensions by using patternArraySummary, designDisplaySnapshot, and objectDimensionSummary to discover clone FeatureIDs and current editable dimensions before dispatching direct feature-dimension commands through AutomationRunner to Core.")
    })
    #expect(!arrays.openWork.contains { $0.contains("output mode editing") })

    let section = try #require(result.entries.first { $0.area == .sectionAnalysis })
    #expect(section.currentRating == .partial)
    #expect(section.referenceSources.contains("https://doc.plasticity.xyz/common/section-analysis"))
    #expect(section.openWork.contains { $0.contains("Exact clipped cap surfaces") })
    #expect(section.evidence.contains { evidence in
        evidence.sourceFiles.contains("RupaKit/Sources/RupaCore/SectionAnalysisService.swift")
    })
    #expect(section.evidence.contains { evidence in
        evidence.sourceFiles.contains("RupaKit/Sources/RupaCore/SectionAnalysisContourBuilder.swift")
    })
    #expect(section.evidence.contains { evidence in
        evidence.sourceFiles.contains("RupaKit/Sources/RupaCore/SectionAnalysisClippingPlan.swift")
    })
    #expect(section.evidence.contains { evidence in
        evidence.sourceFiles.contains("RupaKit/Sources/RupaAutomation/AutomationResult.swift")
    })
    #expect(section.evidence.contains { evidence in
        evidence.sourceFiles.contains("RupaKit/Sources/RupaRendering/ViewportSectionClippingPlan.swift")
    })
    #expect(section.evidence.contains { evidence in
        evidence.sourceFiles.contains("RupaKit/Sources/RupaRendering/ViewportSectionMeshClipper.swift")
    })
    #expect(section.evidence.contains { evidence in
        evidence.sourceFiles.contains("RupaKit/Sources/RupaRendering/ViewportSectionAnalysisOverlay.swift")
    })
    #expect(section.evidence.contains { evidence in
        evidence.sourceFiles.contains("RupaKit/Sources/RupaUI/WorkspaceSectionAnalysisStateBuilder.swift")
    })
    #expect(section.evidence.contains { evidence in
        evidence.tests.contains("RupaKit/Tests/RupaAgentInspectionTests/AgentSectionAnalysisIntegrationTests.swift")
    })
    #expect(section.evidence.contains { evidence in
        evidence.tests.contains("RupaKit/Tests/RupaRenderingTests/ViewportSectionAnalysisOverlayTests.swift")
    })
    #expect(section.evidence.contains { evidence in
        evidence.tests.contains("RupaKit/Tests/RupaRenderingTests/ViewportSectionClippingPlanTests.swift")
    })
    #expect(section.evidence.contains { evidence in
        evidence.tests.contains("RupaKit/Tests/RupaRenderingTests/ViewportSectionMeshClipperTests.swift")
    })
    #expect(section.evidence.contains { evidence in
        evidence.tests.contains("RupaKit/Tests/RupaAgentContractTests/AgentCapabilityContractTests.swift")
    })
    #expect(section.evidence.contains { evidence in
        evidence.notes.contains("Section analysis queries can offset the resolved source plane and flip front/behind classification; the result plane reflects the transformed origin and normal without mutating the section scene node, construction plane, or sketch plane source.")
    })
    #expect(section.evidence.contains { evidence in
        evidence.notes.contains("Body display snapshots and section analysis results preserve generated persistent body identities, source feature IDs, and evaluation-local body IDs so classifications can be mapped back to viewport body items across reevaluation boundaries.")
    })
    #expect(section.evidence.contains { evidence in
        evidence.notes.contains("SectionAnalysisClippingPlan and ViewportSectionClippingPlan classify visible, hidden, and clipped bodies non-mutatingly for retained front or behind section sides.")
    })
    #expect(section.evidence.contains { evidence in
        evidence.notes.contains("Agent and Automation analyzeSection requests can ask for a retained clipping side and receive a SectionAnalysisClippingPlan in the same non-mutating result envelope.")
    })
    #expect(section.evidence.contains { evidence in
        evidence.notes.contains("Viewport section clipping now removes hidden bodies from the rendered and pickable scene and culls mesh triangles to the retained section side without allocating replacement mesh buffers.")
    })
    #expect(section.evidence.contains { evidence in
        evidence.notes.contains("Selecting a section or construction plane can drive a non-mutating viewport overlay that renders the section plane frame, closed section fill, hatching, and bounded body intersection segments from the same SectionAnalysisResult contract used by Agent and Automation.")
    })

    let sketchPrecision = try #require(result.entries.first { $0.area == .sketchPrecision })
    #expect(sketchPrecision.currentRating == .partial)
    #expect(sketchPrecision.referenceSources.contains("https://doc.plasticity.xyz/sketch"))
    #expect(sketchPrecision.openWork.contains { $0.contains("General sketch solver") })

    let surfaceModeling = try #require(result.entries.first { $0.area == .surfaceModeling })
    #expect(surfaceModeling.currentRating == .partial)
    #expect(surfaceModeling.referenceSources.contains("https://doc.plasticity.xyz/cad-essentials/uvn-coordinate-system"))
    #expect(surfaceModeling.evidence.contains { evidence in
        evidence.sourceFiles.contains("RupaKit/Sources/RupaCore/SurfaceFrameService.swift")
    })
    #expect(surfaceModeling.evidence.contains { evidence in
        evidence.sourceFiles.contains("RupaKit/Sources/RupaCore/SnapResolver.swift")
    })
    #expect(surfaceModeling.evidence.contains { evidence in
        evidence.sourceFiles.contains("RupaKit/Sources/RupaRendering/ViewportSurfaceFrameAxisAffordanceGeometry.swift")
    })
    #expect(surfaceModeling.evidence.contains { evidence in
        evidence.tests.contains("RupaKit/Tests/RupaRenderingTests/ViewportSurfaceFrameAxisAffordanceGeometryTests.swift")
    })
    #expect(surfaceModeling.evidence.contains { evidence in
        evidence.notes.contains("Direct B-spline surface sources can be created through Core, Automation, Agent, and CLI, evaluate to selectable sheet topology, appear in surface source summaries with stored degree, knot vectors, weights, control-net references, editable knot and span references, rectangular trim-loop identity, authored trim-loop identity, selectable trim-edge references, Agent-readable authored p-curve control-point summary indices and weights, shared adaptive UV trim-loop validation, rational 2D B-spline p-curve trim preservation, and typed trim-edge continuity capability, and support direct CV position, CV weight, CV slide, internal knot-value mutation, shape-preserving knot insertion, fraction-based span splitting, explicit internal knot multiplicity editing, authored trim endpoint moves with loop-closure preservation, strict interior polyline and 2D B-spline trim p-curve control-point moves, 2D B-spline trim p-curve control-point weight edits, selected viewport trim endpoint handles, selected viewport trim interior control-point handles, authored B-spline trim p-curve span/knot UVN frame resolution and display persistence, and compatible clamped trim-boundary G0/G1/G2 matching with homogeneous inward derivative-scale solving.")
    })
    #expect(surfaceModeling.evidence.contains { evidence in
        evidence.notes.contains { note in
            note.contains("Visible surface frame displays now feed SnapResolver surfaceFrame candidates")
        }
    })
    #expect(surfaceModeling.evidence.contains { evidence in
        evidence.notes.contains("Selected Surface CVs can now use visible viewport surface-frame U/V/N axes as drag handles that commit through the existing Core moveSurfaceControlPointsInFrame contract.")
    })
    #expect(surfaceModeling.openWork.contains { $0.contains("visible-frame snap anchors") })
    #expect(!surfaceModeling.openWork.contains { $0.contains("Interactive viewport surface-frame drag handles") })

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
        evidence.notes.contains("Generated fillet arc edges resolve back to editable source arc radius, diameter, and angle dimensions with radius as the primary target.")
    })
    #expect(dimension.evidence.contains { evidence in
        evidence.notes.contains("Agent expression requests can omit defaults and then resolve unitless length literals through the current document display unit, so site and regional scale edits are not millimeter-locked.")
    })
    #expect(dimension.evidence.contains { evidence in
        evidence.notes.contains("Generated solid face pairs resolve to SwiftCAD selection dimensions and evaluate through the shared CAD kernel.")
    })
    #expect(!dimension.openWork.contains("Fillet-size and sphere dimensions."))
    #expect(dimension.openWork.contains("Sphere primitive source ownership and sphere radius/diameter dimensions."))
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
