import RupaCore
import SwiftCAD
import Testing
@testable import RupaUI

@Test func surfaceParameterInspectorStateReportsEditableInteriorKnotSelection() throws {
    var document = DesignDocument.empty()
    _ = try document.createBSplineSurface(
        name: "Inspector Direct Surface",
        surface: surfaceParameterInspectorDirectBSplineSurface()
    )

    let summary = try SurfaceSourceSummaryService().summarize(
        document: document,
        displayUnit: .millimeter
    )
    let patch = try #require(summary.sources.first?.patches.first)
    let knot = try #require(patch.basis.uKnotVector.first { $0.index == 3 })
    let reference = try #require(knot.selectionReference)
    let state = try #require(SurfaceParameterInspectorState(
        selectedReferences: [reference],
        summaryResult: summary
    ))

    #expect(state.selectionCount == 1)
    #expect(state.sourceTitle == "Inspector Direct Surface")
    #expect(state.patchTitle == "Patch 0")
    #expect(state.basisTitle == "bSplineSurface")
    #expect(state.kindTitle == "Knot")
    #expect(state.directionTitle == "U")
    #expect(state.indexTitle == "k3")
    #expect(state.valueTitle == "0.5")
    #expect(state.multiplicityTitle == "1")
    #expect(state.boundaryTitle == "Interior")
    #expect(state.editabilityTitle == "Editable")
    #expect(state.canSetKnotValue)
    #expect(state.canInsertKnot)
    #expect(state.canSetKnotMultiplicity)
    #expect(state.selectedReferences == [reference])
    #expect(state.clampedKnotValue(0.0) ?? 0.0 > 0.0)
    #expect(state.clampedKnotValue(1.0) ?? 0.0 < 1.0)
    #expect(state.clampedInsertionValue(0.25) == 0.5)
    #expect(state.defaultKnotMultiplicity(fallback: 3) == 2)
    #expect(state.clampedKnotMultiplicity(1) == 2)
    #expect(state.clampedKnotMultiplicity(3) == 2)
}

@Test func surfaceParameterInspectorStateReportsSurfaceParameterAddressSelection() throws {
    var document = DesignDocument.empty()
    _ = try document.createBSplineSurface(
        name: "Inspector Direct Surface",
        surface: surfaceParameterInspectorDirectBSplineSurface()
    )

    let summary = try SurfaceSourceSummaryService().summarize(document: document, displayUnit: .millimeter)
    let patch = try #require(summary.sources.first?.patches.first)
    let address = try #require(patch.parameterAddresses.first { $0.id == "center" })
    let reference = try #require(address.selectionReference)
    let state = try #require(SurfaceParameterInspectorState(
        selectedReferences: [reference],
        summaryResult: summary
    ))

    #expect(state.selectionCount == 1)
    #expect(state.kindTitle == "Address")
    #expect(state.directionTitle == "UV")
    #expect(state.indexTitle == "center")
    #expect(state.valueTitle == "(0.5, 0.5)")
    #expect(state.boundaryTitle == "Interior")
    #expect(state.editabilityTitle == "Frame Query")
    #expect(state.frameDisplayTitle == "Hidden")
    #expect(state.hasResolvedFrames == false)
    #expect(state.canSetKnotValue == false)
    #expect(state.canInsertKnot == false)
    #expect(state.canSetKnotMultiplicity == false)
    #expect(state.canToggleFrameDisplay)
    #expect(state.selectedFrameQueries == [SurfaceFrameQuery(selectionReference: reference)])
}

@Test func surfaceParameterInspectorStateReportsEditableSpanSelection() throws {
    var document = DesignDocument.empty()
    _ = try document.createBSplineSurface(
        name: "Inspector Direct Surface",
        surface: surfaceParameterInspectorDirectBSplineSurface()
    )

    let summary = try SurfaceSourceSummaryService().summarize(document: document, displayUnit: .millimeter)
    let patch = try #require(summary.sources.first?.patches.first)
    let span = try #require(patch.basis.uSpans.first { $0.index == 0 })
    let reference = try #require(span.selectionReference)
    let state = try #require(SurfaceParameterInspectorState(
        selectedReferences: [reference],
        summaryResult: summary
    ))

    #expect(state.selectionCount == 1)
    #expect(state.kindTitle == "Span")
    #expect(state.directionTitle == "U")
    #expect(state.indexTitle == "s0")
    #expect(state.valueTitle == "0 ... 0.5")
    #expect(state.multiplicityTitle == "-")
    #expect(state.boundaryTitle == "Interior")
    #expect(state.editabilityTitle == "Editable")
    #expect(state.canSetKnotValue == false)
    #expect(state.canInsertKnot)
    #expect(state.canSplitSpan)
    #expect(state.canSetKnotMultiplicity == false)
    #expect(state.defaultInsertionValue(fallback: 0.1) == 0.25)
    #expect(state.defaultSpanSplitFraction() == 0.5)
    #expect(state.clampedSpanSplitFraction(-1.0) == 1.0e-6)
    #expect(state.clampedSpanSplitFraction(2.0) == 1.0 - 1.0e-6)
    #expect(state.clampedInsertionValue(0.0) ?? 0.0 > 0.0)
    #expect(state.clampedInsertionValue(0.5) ?? 0.0 < 0.5)
}

@MainActor
@Test func surfaceParameterInspectorStateReportsSurfaceParameterFrameDisplayVisibility() throws {
    let session = EditorSession()
    _ = try #require(session.createBSplineSurface(
        name: "Inspector Direct Surface",
        surface: surfaceParameterInspectorDirectBSplineSurface()
    ))

    let initialSummary = try SurfaceSourceSummaryService().summarize(document: session.document, displayUnit: .millimeter)
    let patch = try #require(initialSummary.sources.first?.patches.first)
    let frameSample = try #require(patch.frameSamples.first)
    let query = SurfaceFrameQuery(selectionReference: frameSample.selectionReference)
    _ = try #require(session.setSurfaceFrameDisplay(
        query: query,
        isVisible: true
    ))

    let visibleSummary = try SurfaceSourceSummaryService().summarize(document: session.document, displayUnit: .millimeter)
    let state = try #require(SurfaceParameterInspectorState(
        selectedReferences: [frameSample.selectionReference],
        summaryResult: visibleSummary,
        surfaceFrameDisplays: session.workspaceState.surfaceFrameDisplays
    ))

    #expect(state.kindTitle == "Address")
    #expect(state.indexTitle.hasPrefix("frame:"))
    #expect(state.frameDisplayTitle == "Visible")
    #expect(state.canToggleFrameDisplay)
    #expect(state.entries.first?.isFrameDisplayVisible == true)
    #expect(state.selectedFrameQueries == [query])
}

@Test func surfaceParameterInspectorStateReportsBoundaryKnotAsReadOnly() throws {
    var document = DesignDocument.empty()
    _ = try document.createBSplineSurface(
        name: "Inspector Direct Surface",
        surface: surfaceParameterInspectorDirectBSplineSurface()
    )

    let summary = try SurfaceSourceSummaryService().summarize(document: document, displayUnit: .millimeter)
    let patch = try #require(summary.sources.first?.patches.first)
    let knot = try #require(patch.basis.uKnotVector.first { $0.index == 0 })
    let reference = try #require(knot.selectionReference)
    let state = try #require(SurfaceParameterInspectorState(
        selectedReferences: [reference],
        summaryResult: summary
    ))

    #expect(state.kindTitle == "Knot")
    #expect(state.boundaryTitle == "Boundary")
    #expect(state.editabilityTitle == "Read Only")
    #expect(state.canSetKnotValue == false)
    #expect(state.canInsertKnot == false)
    #expect(state.canSetKnotMultiplicity == false)
}

@Test func surfaceParameterInspectorStateHidesMultiplicityControlForSaturatedKnot() throws {
    var document = DesignDocument.empty()
    _ = try document.createBSplineSurface(
        name: "Inspector Saturated Knot Surface",
        surface: surfaceParameterInspectorDirectBSplineSurface()
    )

    let summary = try SurfaceSourceSummaryService().summarize(document: document, displayUnit: .millimeter)
    let patch = try #require(summary.sources.first?.patches.first)
    let knot = try #require(patch.basis.uKnotVector.first { $0.index == 3 })
    let reference = try #require(knot.selectionReference)
    try document.setSurfaceKnotMultiplicity(
        target: reference,
        multiplicity: 2
    )

    let updatedSummary = try SurfaceSourceSummaryService().summarize(document: document, displayUnit: .millimeter)
    let updatedPatch = try #require(updatedSummary.sources.first?.patches.first)
    let saturatedKnot = try #require(updatedPatch.basis.uKnotVector.first { $0.index == 3 })
    let saturatedReference = try #require(saturatedKnot.selectionReference)
    let state = try #require(SurfaceParameterInspectorState(
        selectedReferences: [saturatedReference],
        summaryResult: updatedSummary
    ))

    #expect(state.multiplicityTitle == "2")
    #expect(state.canInsertKnot == false)
    #expect(state.canSetKnotMultiplicity == false)
    #expect(state.clampedKnotMultiplicity(2) == nil)
}

@Test func surfaceParameterInspectorStateRejectsNonParameterReferences() throws {
    var document = DesignDocument.empty()
    _ = try document.createBSplineSurface(
        name: "Inspector Direct Surface",
        surface: surfaceParameterInspectorDirectBSplineSurface()
    )

    let summary = try SurfaceSourceSummaryService().summarize(document: document, displayUnit: .millimeter)
    let patch = try #require(summary.sources.first?.patches.first)
    let controlPoint = try #require(patch.controlPoints.first)

    #expect(SurfaceParameterInspectorState(
        selectedReferences: [controlPoint.selectionReference],
        summaryResult: summary
    ) == nil)
}

@Test func workspaceSurfaceInspectorStateBuilderResolvesSurfaceParameterSelection() throws {
    var document = DesignDocument.empty()
    _ = try document.createBSplineSurface(
        name: "Inspector Direct Surface",
        surface: surfaceParameterInspectorDirectBSplineSurface()
    )

    let summary = try SurfaceSourceSummaryService().summarize(document: document, displayUnit: .millimeter)
    let patch = try #require(summary.sources.first?.patches.first)
    let span = try #require(patch.basis.vSpans.first { $0.index == 1 })
    let reference = try #require(span.selectionReference)
    let builder = WorkspaceSurfaceInspectorStateBuilder(
        document: document,
        selection: SelectionModel(selectedReferences: [reference]),
        currentEvaluation: nil,
        documentGeneration: DocumentGeneration(),
        objectRegistry: .builtIn,
        surfaceAnalysisOptions: SurfaceAnalysisOptions(sampleDensity: .standard),
        workspaceState: WorkspaceState()
    )

    let state = try #require(try builder.surfaceParameterStateResult().get())

    #expect(builder.surfaceParameterReferences == [reference])
    #expect(builder.surfaceControlPointReferences.isEmpty)
    #expect(state.selectedReferences == [reference])
    #expect(state.kindTitle == "Span")
    #expect(state.directionTitle == "V")
    #expect(state.indexTitle == "s1")
    #expect(state.canInsertKnot)
}

@MainActor
@Test func workspaceSurfaceInspectorStateBuilderResolvesSurfaceParameterAddressSelection() throws {
    let session = EditorSession()
    _ = try #require(session.createBSplineSurface(
        name: "Inspector Direct Surface",
        surface: surfaceParameterInspectorDirectBSplineSurface()
    ))

    let summary = try SurfaceSourceSummaryService().summarize(document: session.document, displayUnit: .millimeter)
    let patch = try #require(summary.sources.first?.patches.first)
    let address = try #require(patch.parameterAddresses.first { $0.id == "center" })
    let reference = try #require(address.selectionReference)
    let query = SurfaceFrameQuery(selectionReference: reference)
    _ = try #require(session.setSurfaceFrameDisplay(
        query: query,
        isVisible: true
    ))

    let builder = WorkspaceSurfaceInspectorStateBuilder(
        document: session.document,
        selection: SelectionModel(selectedReferences: [reference]),
        currentEvaluation: nil,
        documentGeneration: DocumentGeneration(),
        objectRegistry: .builtIn,
        surfaceAnalysisOptions: SurfaceAnalysisOptions(sampleDensity: .standard),
        workspaceState: session.workspaceState
    )

    let state = try #require(try builder.surfaceParameterStateResult().get())

    #expect(builder.surfaceParameterReferences == [reference])
    #expect(state.kindTitle == "Address")
    #expect(state.frameDisplayTitle == "Visible")
    #expect(state.hasResolvedFrames)
    #expect(state.framePositionTitle == "(0.01, 0.01, 0)")
    #expect(state.frameUAxisTitle == "(1, 0, 0)")
    #expect(state.frameVAxisTitle == "(0, 1, 0)")
    #expect(state.frameNormalTitle == "(0, 0, 1)")
    #expect(state.frameHandednessTitle == "1")
    #expect(state.frameNormalCurvatureTitle == "U 0 1/m, V 0 1/m")
    #expect(state.framePrincipalCurvatureTitle == "Min 0 1/m, Max 0 1/m")
    #expect(state.frameGaussianCurvatureTitle == "0 1/m2")
    #expect(state.selectedFrameQueries == [query])
}

private func surfaceParameterInspectorDirectBSplineSurface() -> BSplineSurface3D {
    let baseSurface = BSplineSurface3D.cubicBezierPatch(
        bottomLeft: Point3D(x: 0.0, y: 0.0, z: 0.0),
        bottomRight: Point3D(x: 0.02, y: 0.0, z: 0.0),
        topRight: Point3D(x: 0.02, y: 0.02, z: 0.0),
        topLeft: Point3D(x: 0.0, y: 0.02, z: 0.0)
    )
    return BSplineSurface3D(
        uDegree: 2,
        vDegree: 2,
        uKnots: [0.0, 0.0, 0.0, 0.5, 1.0, 1.0, 1.0],
        vKnots: [0.0, 0.0, 0.0, 0.5, 1.0, 1.0, 1.0],
        controlPoints: baseSurface.controlPoints
    )
}
