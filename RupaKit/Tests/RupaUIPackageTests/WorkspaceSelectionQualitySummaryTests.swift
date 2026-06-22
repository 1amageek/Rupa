import RupaCore
import Testing
@testable import RupaUI

@Test func workspaceSelectionQualitySummaryMapsSubobjectScopesToSelectionAssessment() throws {
    for scope in [
        WorkspaceSelectionScope.object,
        .face,
        .edge,
        .vertex,
        .region,
    ] {
        let summary = try #require(WorkspaceSelectionQualitySummary(scope: scope))

        #expect(summary.area == .selection)
        #expect(summary.rating == .partial)
        #expect(summary.ratingTitle == "Partial")
        #expect(summary.attentionGate == .viewportAffordance)
        #expect(summary.attentionGateTitle == "Viewport")
        #expect(summary.nextRequiredResult.contains("identity-buffer"))
    }
}

@Test func workspaceSelectionQualitySummaryMapsCurveScopeToCurveContinuityAssessment() throws {
    let summary = try #require(
        WorkspaceSelectionQualitySummary(scope: .sketchEntity)
    )

    #expect(summary.area == .curveContinuity)
    #expect(summary.rating == .partial)
    #expect(summary.attentionGate == .viewportAffordance)
    #expect(summary.nextRequiredResult.contains("Bridge Curve"))
}

@Test func workspaceSelectionQualitySummaryReturnsNilWhenAssessmentEntryIsMissing() {
    let assessment = CADInteractionQualityAssessmentResult(
        referenceDate: "2026-06-22",
        scoringModel: "Test",
        score: 0.0,
        counts: CADInteractionQualityAssessmentCounts(),
        entries: []
    )

    #expect(WorkspaceSelectionQualitySummary(scope: .edge, assessment: assessment) == nil)
}
