import RupaCore
import SwiftCAD
import Testing
@testable import RupaUI

@Test func surfaceControlPointInspectorStateReportsInteriorControlPointSelection() async throws {
    var document = DesignDocument.empty()
    _ = try document.createPolySplineSurface(
        name: "Inspector Surface",
        sourceMesh: surfaceControlPointInspectorPatchNetworkMesh(centerZ: 0.0),
        options: PolySplineOptions(mergePatches: false)
    )

    let summary = try SurfaceSourceSummaryService().summarize(document: document)
    let patch = try #require(summary.sources.first?.patches.first)
    let controlPoint = try #require(patch.controlPoints.first { $0.uIndex == 1 && $0.vIndex == 1 })
    let state = try #require(SurfaceControlPointInspectorState(
        selectedReferences: [controlPoint.selectionReference],
        summaryResult: summary
    ))

    #expect(state.selectionCount == 1)
    #expect(state.sourceTitle == "Inspector Surface")
    #expect(state.patchTitle == "Patch 0")
    #expect(state.basisTitle == "cubicBezierBSpline")
    #expect(state.indexTitle == "u1 / v1")
    #expect(state.roleTitle == "Interior")
    #expect(state.boundaryTitle == "Interior")
    #expect(state.editabilityTitle == "Editable")
    #expect(state.displayTitle == "Hidden")
    #expect(state.canEditCoordinates)
    #expect(state.canSlide)
    #expect(state.canMoveInFrame)
    #expect(state.canEditWeight)
    #expect(state.weightTitle == "1")
    #expect(state.frameTitle == "u1 / v1")
    #expect(state.frameMoveQuery == SurfaceFrameQuery(selectionReference: controlPoint.selectionReference))
    #expect(state.selectedReferences == [controlPoint.selectionReference])
}

@Test func surfaceControlPointInspectorStateReportsCornerControlVertexRole() async throws {
    var document = DesignDocument.empty()
    _ = try document.createPolySplineSurface(
        name: "Inspector Corner Surface",
        sourceMesh: surfaceControlPointInspectorPatchNetworkMesh(centerZ: 0.0),
        options: PolySplineOptions(mergePatches: false)
    )

    let summary = try SurfaceSourceSummaryService().summarize(document: document)
    let patch = try #require(summary.sources.first?.patches.first)
    let corner = try #require(patch.controlPoints.first { $0.uIndex == 0 && $0.vIndex == 0 })
    let state = try #require(SurfaceControlPointInspectorState(
        selectedReferences: [corner.selectionReference],
        summaryResult: summary
    ))

    #expect(state.roleTitle == "uMin:vMin")
    #expect(state.boundaryTitle == "Boundary")
    #expect(state.editabilityTitle == "Editable")
    #expect(state.canEditCoordinates)
    #expect(state.canSlide)
    #expect(state.canEditWeight == false)
    #expect(state.weightTitle == "1")
}

@Test func surfaceControlPointInspectorStateReportsReadOnlyBoundaryControlPoint() async throws {
    var document = DesignDocument.empty()
    _ = try document.createPolySplineSurface(
        name: "Inspector Boundary Surface",
        sourceMesh: surfaceControlPointInspectorPatchNetworkMesh(centerZ: 0.0),
        options: PolySplineOptions(mergePatches: false)
    )

    let summary = try SurfaceSourceSummaryService().summarize(document: document)
    let patch = try #require(summary.sources.first?.patches.first)
    let boundary = try #require(patch.controlPoints.first { $0.uIndex == 1 && $0.vIndex == 0 })
    let state = try #require(SurfaceControlPointInspectorState(
        selectedReferences: [boundary.selectionReference],
        summaryResult: summary
    ))

    #expect(state.roleTitle == "Boundary")
    #expect(state.boundaryTitle == "Boundary")
    #expect(state.editabilityTitle == "Read Only")
    #expect(state.canEditCoordinates == false)
    #expect(state.canSlide == false)
    #expect(state.canMoveInFrame == false)
    #expect(state.canEditWeight == false)
    #expect(state.frameMoveQuery == SurfaceFrameQuery(selectionReference: boundary.selectionReference))
}

@Test func surfaceControlPointInspectorStateAllowsDirectBSplineBoundaryWeightEditing() async throws {
    var document = DesignDocument.empty()
    _ = try document.createBSplineSurface(
        name: "Inspector Direct Surface",
        surface: surfaceControlPointInspectorDirectBSplineSurface()
    )

    let summary = try SurfaceSourceSummaryService().summarize(document: document)
    let patch = try #require(summary.sources.first?.patches.first)
    let boundary = try #require(patch.controlPoints.first { $0.uIndex == 0 && $0.vIndex == 0 })
    let state = try #require(SurfaceControlPointInspectorState(
        selectedReferences: [boundary.selectionReference],
        summaryResult: summary
    ))

    #expect(state.sourceTitle == "Inspector Direct Surface")
    #expect(state.basisTitle == "bSplineSurface")
    #expect(state.boundaryTitle == "Boundary")
    #expect(state.canEditCoordinates)
    #expect(state.canEditWeight)
    #expect(state.weightTitle == "1")
}

@MainActor
@Test func surfaceControlPointInspectorStateReportsDisplayVisibility() async throws {
    let session = EditorSession()
    _ = try #require(session.createPolySplineSurface(
        name: "Inspector Display Surface",
        sourceMesh: surfaceControlPointInspectorPatchNetworkMesh(centerZ: 0.0),
        options: PolySplineOptions(mergePatches: false)
    ))

    let initialSummary = try SurfaceSourceSummaryService().summarize(document: session.document)
    let initialPatch = try #require(initialSummary.sources.first?.patches.first)
    let controlPoint = try #require(initialPatch.controlPoints.first { $0.uIndex == 1 && $0.vIndex == 1 })
    _ = try #require(session.setSurfaceControlPointDisplay(
        target: controlPoint.selectionReference,
        isVisible: true
    ))

    let visibleSummary = try SurfaceSourceSummaryService().summarize(document: session.document)
    let state = try #require(SurfaceControlPointInspectorState(
        selectedReferences: [controlPoint.selectionReference],
        summaryResult: visibleSummary
    ))

    #expect(state.displayTitle == "Visible")
    #expect(state.entries.first?.isPointDisplayVisible == true)
}

@MainActor
@Test func surfaceControlPointInspectorStateReportsFrameDisplayVisibility() async throws {
    let session = EditorSession()
    _ = try #require(session.createPolySplineSurface(
        name: "Inspector Frame Display Surface",
        sourceMesh: surfaceControlPointInspectorPatchNetworkMesh(centerZ: 0.0),
        options: PolySplineOptions(mergePatches: false)
    ))

    let initialSummary = try SurfaceSourceSummaryService().summarize(document: session.document)
    let initialPatch = try #require(initialSummary.sources.first?.patches.first)
    let controlPoint = try #require(initialPatch.controlPoints.first { $0.uIndex == 1 && $0.vIndex == 1 })
    let query = SurfaceFrameQuery(selectionReference: controlPoint.selectionReference)
    _ = try #require(session.setSurfaceFrameDisplay(
        query: query,
        isVisible: true
    ))

    let visibleSummary = try SurfaceSourceSummaryService().summarize(document: session.document)
    let state = try #require(SurfaceControlPointInspectorState(
        selectedReferences: [controlPoint.selectionReference],
        summaryResult: visibleSummary,
        surfaceFrameDisplays: session.document.productMetadata.surfaceFrameDisplays
    ))

    #expect(state.frameDisplayTitle == "Visible")
    #expect(state.selectedFrameQueries == [query])
    #expect(state.entries.first?.isFrameDisplayVisible == true)
}

@Test func surfaceControlPointInspectorStateRejectsUnresolvedOrNonControlPointReferences() async throws {
    var document = DesignDocument.empty()
    _ = try document.createPolySplineSurface(
        name: "Inspector Rejection Surface",
        sourceMesh: surfaceControlPointInspectorPatchNetworkMesh(centerZ: 0.0),
        options: PolySplineOptions(mergePatches: false)
    )

    let summary = try SurfaceSourceSummaryService().summarize(document: document)
    let patch = try #require(summary.sources.first?.patches.first)
    let faceReference = try #require(patch.faceSelectionReference)

    #expect(SurfaceControlPointInspectorState(
        selectedReferences: [faceReference],
        summaryResult: summary
    ) == nil)
}

private func surfaceControlPointInspectorDirectBSplineSurface() -> BSplineSurface3D {
    BSplineSurface3D.cubicBezierPatch(
        bottomLeft: Point3D(x: 0.0, y: 0.0, z: 0.0),
        bottomRight: Point3D(x: 0.02, y: 0.0, z: 0.0),
        topRight: Point3D(x: 0.02, y: 0.02, z: 0.0),
        topLeft: Point3D(x: 0.0, y: 0.02, z: 0.0)
    )
}

private func surfaceControlPointInspectorPatchNetworkMesh(centerZ: Double) -> Mesh {
    Mesh(
        positions: [
            Point3D(x: 0.0, y: 0.0, z: 0.0),
            Point3D(x: 0.01, y: 0.0, z: 0.0),
            Point3D(x: 0.02, y: 0.0, z: 0.0),
            Point3D(x: 0.0, y: 0.01, z: 0.0),
            Point3D(x: 0.01, y: 0.01, z: centerZ),
            Point3D(x: 0.02, y: 0.01, z: 0.0),
        ],
        indices: [
            0, 1, 4,
            0, 4, 3,
            1, 2, 5,
            1, 5, 4,
        ]
    )
}
