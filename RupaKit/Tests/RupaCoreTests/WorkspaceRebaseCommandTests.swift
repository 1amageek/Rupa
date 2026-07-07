import SwiftCAD
import Testing
@testable import RupaCore

@Test(.timeLimit(.minutes(1)))
func workspaceOriginRebaseMovesCADSourcesAndClearsFarOriginPrecisionWarnings() throws {
    let document = try farFromOriginRectangleDocument()
    let initialMeasurement = try MeasurementService(
        tolerance: .workspaceScaleAware(for: document)
    ).measure(document: document)
    #expect(initialMeasurement.diagnostics.contains { $0.code == .workspacePrecisionWarning })

    let session = EditorSession(document: document)
    let result = try session.execute(.rebaseWorkspaceOrigin(
        translation: Vector3D(x: -1.0e12, y: -1.0e12, z: 0.0)
    ))

    #expect(result.commandName == "rebaseWorkspaceOrigin")
    #expect(result.didMutate)
    #expect(result.generation == DocumentGeneration(1))
    #expect(result.diagnostics.contains { $0.code == .workspacePrecisionWarning } == false)

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
    #expect(translatedMeasurement.diagnostics.contains { $0.code == .workspacePrecisionWarning } == false)
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

@Test(.timeLimit(.minutes(1)))
func farFromOriginExtrudeMeasuresWithoutUnsupportedProfile() throws {
    let document = try farFromOriginRectangleDocument()
    let measurement = try MeasurementService(
        tolerance: .workspaceScaleAware(for: document)
    ).measure(document: document)

    // The 10 m x 10 m profile sits at 1e12 coordinates. A raw shoelace area
    // collapses to zero there (catastrophic cancellation), which used to skip
    // the extrude as an "unsupported profile". The origin-rebased area keeps it
    // exact, so the extrude is measured with its true 1000 m^3 volume.
    #expect(measurement.diagnostics.allSatisfy { !$0.message.contains("unsupported profile") })
    #expect(abs(measurement.totals.solidVolumeCubicMeters - 1000.0) < 1.0e-3)
}

@Test(.timeLimit(.minutes(1)))
func farFromOriginLoopStitchingAcceptsCoordinateResolutionGap() throws {
    let document = try farFromOriginAlmostClosedRectangleDocument()
    let measurement = try MeasurementService().measure(document: document)

    #expect(measurement.diagnostics.allSatisfy { !$0.message.contains("unsupported profile") })
    #expect(measurement.counts.solids == 1)
    // The intentionally retained one-ULP endpoint gap may contribute to area
    // depending on dictionary iteration order, but the profile must not be skipped.
    #expect(abs(measurement.totals.solidVolumeCubicMeters - 1000.0) < 1.0e-2)
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

private func farFromOriginAlmostClosedRectangleDocument() throws -> DesignDocument {
    var document = DesignDocument.empty(named: "Remote Nearly Closed Profile")
    let origin = 1.0e12
    let side = 10.0
    let high = origin + side
    let highNext = high.nextUp
    let sketchFeatureID = FeatureID()
    let extrudeFeatureID = FeatureID()
    let sketch = Sketch(
        plane: .xy,
        entities: [
            SketchEntityID(): .line(SketchLine(
                start: SketchPoint(
                    x: .length(origin, .meter),
                    y: .length(origin, .meter)
                ),
                end: SketchPoint(
                    x: .length(high, .meter),
                    y: .length(origin, .meter)
                )
            )),
            SketchEntityID(): .line(SketchLine(
                start: SketchPoint(
                    x: .length(highNext, .meter),
                    y: .length(origin, .meter)
                ),
                end: SketchPoint(
                    x: .length(high, .meter),
                    y: .length(high, .meter)
                )
            )),
            SketchEntityID(): .line(SketchLine(
                start: SketchPoint(
                    x: .length(high, .meter),
                    y: .length(high, .meter)
                ),
                end: SketchPoint(
                    x: .length(origin, .meter),
                    y: .length(high, .meter)
                )
            )),
            SketchEntityID(): .line(SketchLine(
                start: SketchPoint(
                    x: .length(origin, .meter),
                    y: .length(high, .meter)
                ),
                end: SketchPoint(
                    x: .length(origin, .meter),
                    y: .length(origin, .meter)
                )
            )),
        ]
    )
    try document.cadDocument.appendFeature(FeatureNode(
        id: sketchFeatureID,
        name: "Remote Almost Closed Profile",
        operation: .sketch(sketch),
        outputs: [FeatureOutput(role: .profile)]
    ))
    try document.cadDocument.appendFeature(FeatureNode(
        id: extrudeFeatureID,
        name: "Remote Almost Closed Solid",
        operation: .extrude(ExtrudeFeature(
            profile: ProfileReference(featureID: sketchFeatureID),
            distance: .length(10.0, .meter),
            direction: .normal
        )),
        inputs: [FeatureInput(featureID: sketchFeatureID, role: .profile)],
        outputs: [FeatureOutput(role: .body)]
    ))
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
