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

    let summary = try SurfaceSourceSummaryService().summarize(document: document)
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
    #expect(state.selectedReferences == [reference])
    #expect(state.clampedKnotValue(0.0) ?? 0.0 > 0.0)
    #expect(state.clampedKnotValue(1.0) ?? 0.0 < 1.0)
    #expect(state.clampedInsertionValue(0.25) == 0.5)
}

@Test func surfaceParameterInspectorStateReportsEditableSpanSelection() throws {
    var document = DesignDocument.empty()
    _ = try document.createBSplineSurface(
        name: "Inspector Direct Surface",
        surface: surfaceParameterInspectorDirectBSplineSurface()
    )

    let summary = try SurfaceSourceSummaryService().summarize(document: document)
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
    #expect(state.defaultInsertionValue(fallback: 0.1) == 0.25)
    #expect(state.clampedInsertionValue(0.0) ?? 0.0 > 0.0)
    #expect(state.clampedInsertionValue(0.5) ?? 0.0 < 0.5)
}

@Test func surfaceParameterInspectorStateReportsBoundaryKnotAsReadOnly() throws {
    var document = DesignDocument.empty()
    _ = try document.createBSplineSurface(
        name: "Inspector Direct Surface",
        surface: surfaceParameterInspectorDirectBSplineSurface()
    )

    let summary = try SurfaceSourceSummaryService().summarize(document: document)
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
}

@Test func surfaceParameterInspectorStateRejectsNonParameterReferences() throws {
    var document = DesignDocument.empty()
    _ = try document.createBSplineSurface(
        name: "Inspector Direct Surface",
        surface: surfaceParameterInspectorDirectBSplineSurface()
    )

    let summary = try SurfaceSourceSummaryService().summarize(document: document)
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

    let summary = try SurfaceSourceSummaryService().summarize(document: document)
    let patch = try #require(summary.sources.first?.patches.first)
    let span = try #require(patch.basis.vSpans.first { $0.index == 1 })
    let reference = try #require(span.selectionReference)
    let builder = WorkspaceSurfaceInspectorStateBuilder(
        document: document,
        selection: SelectionModel(selectedReferences: [reference]),
        currentEvaluation: nil,
        documentGeneration: DocumentGeneration(),
        objectRegistry: .builtIn,
        surfaceAnalysisOptions: SurfaceAnalysisOptions(sampleDensity: .standard)
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
