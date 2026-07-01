import SwiftCAD
import Testing
@testable import RupaCore

@Test(.timeLimit(.minutes(1)))
func workspaceOriginRebaseMovesCADSourcesAndClearsFarOriginPrecisionWarnings() throws {
    let document = try farFromOriginRectangleDocument()
    let initialMeasurement = try MeasurementService(
        tolerance: .workspaceScaleAware(for: document)
    ).measure(document: document)
    #expect(initialMeasurement.diagnostics.contains { $0.message.contains("Workspace precision warning") })

    let session = EditorSession(document: document)
    let result = try session.execute(.rebaseWorkspaceOrigin(
        translation: Vector3D(x: -1.0e12, y: -1.0e12, z: 0.0)
    ))

    #expect(result.commandName == "rebaseWorkspaceOrigin")
    #expect(result.didMutate)
    #expect(result.generation == DocumentGeneration(1))
    #expect(result.diagnostics.contains { $0.message.contains("Workspace precision warning") } == false)

    let translatedSketch = try firstSketch(in: session.document.cadDocument)
    let translatedRange = try resolvedSketchCoordinateRange(
        in: translatedSketch,
        document: session.document.cadDocument
    )
    #expect(abs(translatedRange.minX) < 1.0e-6)
    #expect(abs(translatedRange.minY) < 1.0e-6)
    #expect(abs(translatedRange.maxX - 10.0) < 1.0e-6)
    #expect(abs(translatedRange.maxY - 10.0) < 1.0e-6)

    let translatedMeasurement = try MeasurementService(
        tolerance: .workspaceScaleAware(for: session.document)
    ).measure(document: session.document)
    #expect(translatedMeasurement.diagnostics.contains { $0.message.contains("Workspace precision warning") } == false)
}

@Test(.timeLimit(.minutes(1)))
func workspaceOriginRebaseRejectsStandardPlaneNormalTranslationWithoutMutation() throws {
    let document = try farFromOriginRectangleDocument()
    let session = EditorSession(document: document)

    #expect(throws: FeatureEvaluationError.self) {
        try session.execute(.rebaseWorkspaceOrigin(
            translation: Vector3D(x: -1.0e12, y: -1.0e12, z: 5.0)
        ))
    }
    #expect(session.generation == DocumentGeneration(0))

    let sketch = try firstSketch(in: session.document.cadDocument)
    let range = try resolvedSketchCoordinateRange(in: sketch, document: session.document.cadDocument)
    #expect(abs(range.minX - 1.0e12) < 1.0e-3)
    #expect(abs(range.minY - 1.0e12) < 1.0e-3)
}

private func farFromOriginRectangleDocument() throws -> DesignDocument {
    var document = DesignDocument.empty(named: "Remote Site")
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

private func firstSketch(in document: CADDocument) throws -> Sketch {
    for featureID in document.designGraph.order {
        guard let node = document.designGraph.nodes[featureID] else {
            continue
        }
        if case .sketch(let sketch) = node.operation {
            return sketch
        }
    }
    Issue.record("Expected a sketch feature.")
    return Sketch(plane: .xy)
}

private func resolvedSketchCoordinateRange(
    in sketch: Sketch,
    document: CADDocument
) throws -> (minX: Double, minY: Double, maxX: Double, maxY: Double) {
    var points: [SketchPoint] = []
    for entity in sketch.entities.values {
        switch entity {
        case .point(let point):
            points.append(point)
        case .line(let line):
            points.append(line.start)
            points.append(line.end)
        case .circle(let circle):
            points.append(circle.center)
        case .arc(let arc):
            points.append(arc.center)
        case .spline(let spline):
            points.append(contentsOf: spline.controlPoints)
        }
    }
    let resolvedPoints = try points.map { point in
        (
            x: try resolvedLength(point.x, document: document),
            y: try resolvedLength(point.y, document: document)
        )
    }
    let first = try #require(resolvedPoints.first)
    var range = (minX: first.x, minY: first.y, maxX: first.x, maxY: first.y)
    for point in resolvedPoints.dropFirst() {
        range.minX = min(range.minX, point.x)
        range.minY = min(range.minY, point.y)
        range.maxX = max(range.maxX, point.x)
        range.maxY = max(range.maxY, point.y)
    }
    return range
}

private func resolvedLength(
    _ expression: CADExpression,
    document: CADDocument
) throws -> Double {
    let quantity = try document.parameters.resolvedValue(for: expression)
    #expect(quantity.kind == .length)
    return quantity.value
}
