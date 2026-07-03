import RupaCore
import SwiftCAD
import Testing
@testable import RupaUI

@Test func workspaceReferenceContextSummaryReportsSingleSurfaceKnot() {
    let reference = SelectionReference.surface(.knot(SurfaceKnotReference(
        surface: workspaceReferenceContextSummarySurface(),
        direction: .u,
        knotIndex: 3
    )))

    let summary = WorkspaceReferenceContextSummary(references: [reference])

    #expect(summary.referenceCount == 1)
    #expect(summary.familyTitle == "Surface")
    #expect(summary.kindTitle == "Knot")
    #expect(summary.directionTitle == "U")
    #expect(summary.indexTitle == "k3")
    #expect(!summary.showsReferenceCount)
}

@Test func workspaceReferenceContextSummaryReportsCommonSurfaceSpanDirection() {
    let surface = workspaceReferenceContextSummarySurface()
    let references = [
        SelectionReference.surface(.span(SurfaceSpanReference(
            surface: surface,
            direction: .v,
            spanIndex: 1
        ))),
        SelectionReference.surface(.span(SurfaceSpanReference(
            surface: surface,
            direction: .v,
            spanIndex: 2
        )))
    ]

    let summary = WorkspaceReferenceContextSummary(references: references)

    #expect(summary.referenceCount == 2)
    #expect(summary.familyTitle == "Surface")
    #expect(summary.kindTitle == "Span")
    #expect(summary.directionTitle == "V")
    #expect(summary.indexTitle == nil)
    #expect(summary.showsReferenceCount)
}

@Test func workspaceReferenceContextSummaryReportsSurfaceParameterAddress() {
    let reference = SelectionReference.surface(.parameter(SurfaceParameterReference(
        surface: workspaceReferenceContextSummarySurface(),
        u: 0.25,
        v: 0.5
    )))

    let summary = WorkspaceReferenceContextSummary(references: [reference])

    #expect(summary.familyTitle == "Surface")
    #expect(summary.kindTitle == "Address")
    #expect(summary.directionTitle == "UV")
    #expect(summary.indexTitle == "u0.25 v0.5")
}

@Test func workspaceReferenceContextSummaryReportsTrimKnotReference() {
    let reference = SelectionReference.surface(.trimKnot(SurfaceTrimKnotReference(
        trim: SurfaceTrimReference(
            surface: workspaceReferenceContextSummarySurface(),
            loopIndex: 1,
            edgeIndex: 2
        ),
        knotIndex: 4
    )))

    let summary = WorkspaceReferenceContextSummary(references: [reference])

    #expect(summary.familyTitle == "Trim")
    #expect(summary.kindTitle == "Knot")
    #expect(summary.directionTitle == nil)
    #expect(summary.indexTitle == "l1 e2 k4")
}

@Test func workspaceReferenceContextSummaryReportsMixedReferenceFamilies() {
    let surface = workspaceReferenceContextSummarySurface()
    let references = [
        SelectionReference.surface(.knot(SurfaceKnotReference(
            surface: surface,
            direction: .u,
            knotIndex: 1
        ))),
        SelectionReference.edge(.whole(EdgeReference(
            edgeName: PersistentName(components: [.generated("edge")])
        )))
    ]

    let summary = WorkspaceReferenceContextSummary(references: references)

    #expect(summary.referenceCount == 2)
    #expect(summary.familyTitle == "Mixed")
    #expect(summary.kindTitle == "Mixed")
    #expect(summary.directionTitle == nil)
    #expect(summary.indexTitle == nil)
    #expect(summary.systemImage == "scope")
}

private func workspaceReferenceContextSummarySurface() -> SurfaceReference {
    SurfaceReference(faceName: PersistentName(components: [.generated("surface")]))
}
