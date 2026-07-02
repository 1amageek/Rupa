import SwiftCAD
import Testing
@testable import RupaCore

@Test func workspacePrecisionDiagnosticsIgnoreLargeSiteModelNearOrigin() {
    let bounds = MeasurementResult.Bounds(
        minX: 0.0,
        minY: 0.0,
        minZ: 0.0,
        maxX: 100_000.0,
        maxY: 20_000.0,
        maxZ: 500.0
    )

    let diagnostics = WorkspacePrecisionDiagnosticService().diagnostics(
        for: bounds,
        ruler: WorkspaceScalePreset.sitePlanning.rulerConfiguration,
        displayUnit: .kilometer
    )

    #expect(diagnostics.isEmpty)
}

@Test func workspacePrecisionDiagnosticsWarnWhenCoordinateResolutionExceedsBudget() {
    let bounds = MeasurementResult.Bounds(
        minX: 1.0e12,
        minY: 1.0e12,
        minZ: 0.0,
        maxX: 1.0e12 + 10.0,
        maxY: 1.0e12 + 10.0,
        maxZ: 10.0
    )

    let diagnostics = WorkspacePrecisionDiagnosticService().diagnostics(
        for: bounds,
        ruler: WorkspaceScalePreset.sitePlanning.rulerConfiguration,
        displayUnit: .kilometer
    )

    #expect(diagnostics.count == 1)
    #expect(diagnostics.first?.severity == .warning)
    #expect(diagnostics.first?.message.contains("floating-point coordinate resolution") == true)
    #expect(diagnostics.first?.message.contains("local origin") == true)

    let report = WorkspacePrecisionDiagnosticService().report(
        for: bounds,
        ruler: WorkspaceScalePreset.sitePlanning.rulerConfiguration
    )
    #expect(report?.reason == .coordinateResolution)
    #expect(report?.modelCenter == Point3D(x: 1.0e12 + 5.0, y: 1.0e12 + 5.0, z: 5.0))
    #expect(report?.recommendedRebaseTranslation == Vector3D(
        x: -(1.0e12 + 5.0),
        y: -(1.0e12 + 5.0),
        z: 0.0
    ))
}

@Test func workspacePrecisionDiagnosticsNoticeSmallModelFarFromOrigin() {
    let bounds = MeasurementResult.Bounds(
        minX: 10_000.0,
        minY: 10_000.0,
        minZ: 0.0,
        maxX: 10_000.001,
        maxY: 10_000.001,
        maxZ: 0.001
    )

    let diagnostics = WorkspacePrecisionDiagnosticService().diagnostics(
        for: bounds,
        ruler: .standard(for: .millimeter),
        displayUnit: .millimeter
    )

    #expect(diagnostics.count == 1)
    #expect(diagnostics.first?.severity == .info)
    #expect(diagnostics.first?.message.contains("Workspace precision notice") == true)
    #expect(diagnostics.first?.message.contains("rebase workflow") == true)
}

@MainActor
@Test func evaluationSnapshotIncludesWorkspacePrecisionDiagnostic() throws {
    let document = try farFromOriginDocument()

    let snapshot = EvaluationScheduler().evaluate(
        document: document,
        generation: DocumentGeneration(1)
    )

    #expect(snapshot.status == .valid)
    #expect(snapshot.diagnostics.contains {
        $0.severity == .warning
            && $0.message.contains("Workspace precision warning")
    })
}

@MainActor
@Test func measurementIncludesWorkspacePrecisionDiagnostic() throws {
    let document = try farFromOriginDocument()

    let result = try MeasurementService(
        tolerance: .workspaceScaleAware(for: document)
    ).measure(document: document)

    #expect(result.diagnostics.contains {
        $0.severity == .warning
            && $0.message.contains("Workspace precision warning")
    })
    #expect(result.workspacePrecision?.reason == .coordinateResolution)
    #expect(result.workspacePrecision?.recommendedRebaseTranslation == Vector3D(
        x: -(1.0e12 + 5.0),
        y: -(1.0e12 + 5.0),
        z: 0.0
    ))
}

@MainActor
@Test func meshSummaryIncludesWorkspacePrecisionDiagnostic() throws {
    let document = try farFromOriginDocument()

    let result = try MeshSummaryService().summarize(document: document)

    #expect(result.diagnostics.contains {
        $0.severity == .warning
            && $0.message.contains("Workspace precision warning")
    })
}

@MainActor
@Test func workspacePrecisionReportCanBeReadFromEvaluatedDocumentForInspectorActions() throws {
    let document = try farFromOriginDocument()
    let evaluated = try DocumentEvaluator.modelingDefault(for: document).evaluate(document.cadDocument)

    let bounds = WorkspaceBoundsService().bounds(for: evaluated)
    let report = WorkspacePrecisionDiagnosticService().report(
        for: evaluated,
        ruler: document.ruler
    )

    #expect(bounds?.sizeX == 10.0)
    #expect(bounds?.sizeY == 10.0)
    #expect(bounds?.sizeZ == 10.0)
    #expect(bounds?.maximumSpan == 10.0)
    #expect(bounds?.maximumAbsoluteCoordinate == 1.0e12 + 10.0)
    #expect(report?.reason == .coordinateResolution)
    #expect(report?.recommendedRebaseTranslation == Vector3D(
        x: -(1.0e12 + 5.0),
        y: -(1.0e12 + 5.0),
        z: 0.0
    ))
}

@MainActor
@Test func workspacePrecisionReportIncludesEvaluatedCurvesForSketchOnlyDocuments() throws {
    var document = DesignDocument.empty(named: "Remote Sketch")
    try document.setRulerConfiguration(WorkspaceScalePreset.sitePlanning.rulerConfiguration)
    _ = try document.createRectangleSketchFromCorners(
        name: "Remote Sketch Profile",
        plane: .xy,
        firstCorner: SketchPoint(
            x: .length(1.0e12, .meter),
            y: .length(1.0e12, .meter)
        ),
        oppositeCorner: SketchPoint(
            x: .length(1.0e12 + 10.0, .meter),
            y: .length(1.0e12 + 10.0, .meter)
        )
    )
    let evaluated = try DocumentEvaluator.modelingDefault(for: document).evaluate(document.cadDocument)

    let bounds = WorkspaceBoundsService().bounds(for: evaluated)
    let report = WorkspacePrecisionDiagnosticService().report(
        for: evaluated,
        ruler: document.ruler
    )

    #expect(bounds?.sizeX == 10.0)
    #expect(bounds?.sizeY == 10.0)
    #expect(bounds?.sizeZ == 0.0)
    #expect(bounds?.maximumSpan == 10.0)
    #expect(bounds?.maximumAbsoluteCoordinate == 1.0e12 + 10.0)
    #expect(report?.reason == .coordinateResolution)
    #expect(report?.recommendedRebaseTranslation == Vector3D(
        x: -(1.0e12 + 5.0),
        y: -(1.0e12 + 5.0),
        z: 0.0
    ))
}

@MainActor
private func farFromOriginDocument() throws -> DesignDocument {
    var document = DesignDocument.empty(named: "Far Origin")
    try document.setRulerConfiguration(WorkspaceScalePreset.sitePlanning.rulerConfiguration)
    let profileID = try document.createRectangleSketchFromCorners(
        name: "Remote Profile",
        plane: .xy,
        firstCorner: SketchPoint(
            x: .length(1.0e12, .meter),
            y: .length(1.0e12, .meter)
        ),
        oppositeCorner: SketchPoint(
            x: .length(1.0e12 + 10.0, .meter),
            y: .length(1.0e12 + 10.0, .meter)
        )
    )
    _ = try document.extrudeProfile(
        name: "Remote Solid",
        profile: ProfileReference(featureID: profileID),
        distance: .length(10.0, .meter),
        direction: .normal
    )
    return document
}
