import Foundation
import SwiftCAD
import Testing
@testable import RupaCore

@Test func defaultDocumentUsesMetersInternally() async throws {
    let document = DesignDocument.empty()
    #expect(document.cadDocument.units.length.rawValue == "meter")
    #expect(document.cadDocument.units.angle.rawValue == "radian")
}

@Test func lengthDisplayUnitsCoverMicrometerThroughMeter() async throws {
    #expect(LengthDisplayUnit.micrometer.metersPerUnit == 0.000_001)
    #expect(LengthDisplayUnit.meter.metersPerUnit == 1.0)
}

@Test func rulerTracksSelectedDisplayUnit() async throws {
    var document = DesignDocument.empty()
    document.setDisplayUnit(.micrometer)

    #expect(document.displayUnit == .micrometer)
    #expect(abs(document.ruler.minorTickMeters - 0.000_001) < 0.000_000_000_001)
    #expect(abs(document.ruler.majorTickMeters - 0.000_01) < 0.000_000_000_001)
}

@Test func rectangleGeneratedRepresentationFollowsExtrusionProperty() async throws {
    let definition = try #require(ObjectTypeCatalog.definition(for: .rectangle))
    #expect(definition.sourceRepresentation == .twoDimensional)
    #expect(definition.generatedRepresentation(for: definition.defaultProperties) == .twoDimensional)

    var properties = definition.defaultProperties
    properties["extrusion"] = .length(0.25)

    #expect(definition.generatedRepresentation(for: properties) == .threeDimensional)
}

@Test func builtInObjectCatalogContainsOnlyImplementedSourceTypes() async throws {
    #expect(ObjectTypeCatalog.definition(for: .line) != nil)
    #expect(ObjectTypeCatalog.definition(for: .rectangle) != nil)
    #expect(ObjectTypeCatalog.definition(for: .circle) != nil)
    #expect(ObjectTypeCatalog.definition(for: .polygon) != nil)
    #expect(ObjectTypeCatalog.definition(for: .cube) != nil)
    #expect(ObjectTypeCatalog.definition(for: .cylinder) != nil)
    #expect(ObjectTypeCatalog.definition(for: .polySpline) != nil)
    #expect(ObjectTypeCatalog.definition(for: .path) == nil)
    #expect(ObjectTypeCatalog.definition(for: .sphere) == nil)
    #expect(ObjectTypeCatalog.definition(for: .torus) == nil)
}

@Test func polygonSketchCreatesClosedEqualLengthLineLoop() async throws {
    var document = DesignDocument.empty()

    let featureID = try document.createPolygonSketch(
        name: "Hexagon",
        plane: .xy,
        center: SketchPoint(
            x: .length(1.0, .millimeter),
            y: .length(2.0, .millimeter)
        ),
        radius: .length(10.0, .millimeter),
        sides: 6,
        rotationAngle: .angle(-90.0, .degree)
    )

    let feature = try #require(document.cadDocument.designGraph.nodes[featureID])
    guard case .sketch(let sketch) = feature.operation else {
        Issue.record("Expected a sketch feature.")
        return
    }
    let lines = sketch.entities.values.compactMap { entity -> SketchLine? in
        if case .line(let line) = entity {
            return line
        }
        return nil
    }
    let node = try #require(document.productMetadata.sceneNodes.values.first {
        $0.reference?.featureID == featureID
    })

    #expect(lines.count == 6)
    #expect(sketch.constraints.count == 11)
    #expect(sketch.constraints.filter { constraint in
        if case .coincident = constraint {
            return true
        }
        return false
    }.count == 6)
    #expect(sketch.constraints.filter { constraint in
        if case .equalLength = constraint {
            return true
        }
        return false
    }.count == 5)
    #expect(node.object?.typeID == .polygon)
    #expect(node.object?.geometryRole == .sketchProfile)
    #expect(node.object?.properties["radius"] == .length(0.01))
    #expect(node.object?.properties["sizing.radius"] == .length(0.01))
    #expect(node.object?.properties["radius.is.inradius"] == .boolean(false))
    #expect(node.object?.properties["inclination.mode"] == .text(PolygonInclinationMode.vertical.rawValue))
    #expect(node.object?.properties["sides.x"] == .integer(6))
    #expect(node.object?.properties["angle"] == .angle(270.0))

    let centerX = 0.001
    let centerY = 0.002
    let radius = 0.01
    for line in lines {
        let start = try resolvedSketchPoint(line.start, in: document)
        let end = try resolvedSketchPoint(line.end, in: document)
        #expect(abs(distance(from: start, to: (centerX, centerY)) - radius) <= 1.0e-12)
        #expect(abs(distance(from: end, to: (centerX, centerY)) - radius) <= 1.0e-12)
        #expect(abs(distance(from: start, to: end) - radius) <= 1.0e-12)
    }
}

@Test func polygonSketchSupportsInradiusSizingMode() async throws {
    var document = DesignDocument.empty()

    let featureID = try document.createPolygonSketch(
        name: "Inradius Square",
        plane: .xy,
        center: SketchPoint(
            x: .length(0.0, .millimeter),
            y: .length(0.0, .millimeter)
        ),
        radius: .length(10.0, .millimeter),
        sides: 4,
        sizingMode: .inradius,
        rotationAngle: .angle(45.0, .degree)
    )

    let feature = try #require(document.cadDocument.designGraph.nodes[featureID])
    guard case .sketch(let sketch) = feature.operation else {
        Issue.record("Expected a sketch feature.")
        return
    }
    let lines = sketch.entities.values.compactMap { entity -> SketchLine? in
        if case .line(let line) = entity {
            return line
        }
        return nil
    }
    let node = try #require(document.productMetadata.sceneNodes.values.first {
        $0.reference?.featureID == featureID
    })
    let inradius = 0.01
    let expectedCircumradius = inradius / cos(Double.pi / 4.0)
    let expectedSideLength = inradius * 2.0 * tan(Double.pi / 4.0)

    #expect(lines.count == 4)
    #expect(node.object?.properties["radius"] == .length(expectedCircumradius))
    #expect(node.object?.properties["sizing.radius"] == .length(inradius))
    #expect(node.object?.properties["radius.is.inradius"] == .boolean(true))
    #expect(node.object?.properties["inclination.mode"] == .text(PolygonInclinationMode.vertical.rawValue))
    #expect(node.object?.properties["side.length"] == .length(expectedSideLength))

    for line in lines {
        let start = try resolvedSketchPoint(line.start, in: document)
        let end = try resolvedSketchPoint(line.end, in: document)
        #expect(abs(distance(from: start, to: (0.0, 0.0)) - expectedCircumradius) <= 1.0e-12)
        #expect(abs(distance(from: end, to: (0.0, 0.0)) - expectedCircumradius) <= 1.0e-12)
        #expect(abs(distance(from: start, to: end) - expectedSideLength) <= 1.0e-12)
        #expect(abs(distanceFromOrigin(toLineFrom: start, to: end) - inradius) <= 1.0e-12)
    }
}

@Test func polygonSketchRejectsInvalidSideCounts() async throws {
    var document = DesignDocument.empty()

    #expect(throws: EditorError.self) {
        _ = try document.createPolygonSketch(
            name: "Invalid Polygon",
            plane: .xy,
            center: SketchPoint(
                x: .length(0.0, .millimeter),
                y: .length(0.0, .millimeter)
            ),
            radius: .length(10.0, .millimeter),
            sides: 2
        )
    }
}

@Test func polySplineSurfaceCreatesTypedSheetObject() async throws {
    var document = DesignDocument.empty()

    let featureID = try document.createPolySplineSurface(
        name: "Quad Surface",
        sourceMesh: designDocumentPolySplineQuadMesh()
    )

    let feature = try #require(document.cadDocument.designGraph.nodes[featureID])
    guard case let .polySpline(polySpline) = feature.operation else {
        Issue.record("Expected a PolySpline feature.")
        return
    }
    #expect(polySpline.sourceMesh.positions.count == 4)
    #expect(feature.outputs == [FeatureOutput(role: .sheet)])
    let node = try #require(document.productMetadata.sceneNodes.values.first {
        $0.reference?.featureID == featureID
    })
    #expect(node.reference?.kind == .body)
    #expect(node.object?.typeID == .polySpline)
    #expect(node.object?.category == .body)
    #expect(node.object?.geometryRole == .surface)
    #expect(node.object?.properties["patch.count"] == .integer(1))
    #expect(node.object?.properties["control.point.u"] == .integer(4))
    #expect(node.object?.properties["control.point.v"] == .integer(4))
    #expect(node.object?.properties["merge.patches"] == .boolean(true))
    #expect(node.object?.properties["interpolate.boundary"] == .boolean(true))
}

@Test func polySplineSurfaceVertexMoveMutatesSourceBoundaryVertex() async throws {
    var document = DesignDocument.empty()

    let featureID = try document.createPolySplineSurface(
        name: "Editable Quad Surface",
        sourceMesh: designDocumentPolySplineQuadMesh()
    )
    let topology = try TopologySummaryService().summarize(document: document)
    let vertexEntry = try #require(topology.entries.first {
        $0.kind == .vertex
            && $0.subshapeRole == "patch:0:vertex:uMax:vMax"
    })
    let target = try #require(vertexEntry.selectionTarget())

    try document.movePolySplineSurfaceVertex(
        target: target,
        deltaX: .length(0.0, .millimeter),
        deltaY: .length(0.0, .millimeter),
        deltaZ: .length(1.0, .millimeter)
    )

    let feature = try #require(document.cadDocument.designGraph.nodes[featureID])
    guard case let .polySpline(polySpline) = feature.operation else {
        Issue.record("Expected a PolySpline feature.")
        return
    }
    #expect(abs(polySpline.sourceMesh.positions[2].z - 0.005) <= 1.0e-12)

    let analysis = try SurfaceAnalysisService(options: SurfaceAnalysisOptions(sampleDensity: .low))
        .analyze(document: document)
    let face = try #require(analysis.faces.first)
    let trimBoundary = try #require(face.trimBoundaries.first)
    #expect(trimBoundary.points.contains { point in
        abs(point.x - 0.02) <= 1.0e-12
            && abs(point.y - 0.02) <= 1.0e-12
            && abs(point.z - 0.005) <= 1.0e-12
    })
}

@Test func surfaceControlPointReferenceMoveMutatesSourceBoundaryVertex() async throws {
    var document = DesignDocument.empty()

    let featureID = try document.createPolySplineSurface(
        name: "Surface Reference Quad Surface",
        sourceMesh: designDocumentPolySplineQuadMesh()
    )
    let summary = try SurfaceSourceSummaryService().summarize(document: document)
    let source = try #require(summary.sources.first)
    let patch = try #require(source.patches.first)
    let controlVertex = try #require(patch.controlVertices.first { $0.role == "uMax:vMax" })

    try document.moveSurfaceControlPoint(
        target: controlVertex.selectionReference,
        deltaX: .length(0.0, .millimeter),
        deltaY: .length(0.0, .millimeter),
        deltaZ: .length(1.0, .millimeter)
    )

    let feature = try #require(document.cadDocument.designGraph.nodes[featureID])
    guard case let .polySpline(polySpline) = feature.operation else {
        Issue.record("Expected a PolySpline feature.")
        return
    }
    #expect(abs(polySpline.sourceMesh.positions[2].z - 0.005) <= 1.0e-12)
}

@Test func surfaceControlPointReferenceMoveMutatesInteriorControlPointOverride() async throws {
    var document = DesignDocument.empty()

    let featureID = try document.createPolySplineSurface(
        name: "Interior Surface Reference Quad Surface",
        sourceMesh: designDocumentPolySplineQuadMesh()
    )
    let summary = try SurfaceSourceSummaryService().summarize(document: document)
    let source = try #require(summary.sources.first)
    let patch = try #require(source.patches.first)
    let controlPoint = try #require(patch.controlPoints.first { $0.uIndex == 1 && $0.vIndex == 1 })

    try document.moveSurfaceControlPoint(
        target: controlPoint.selectionReference,
        deltaX: .length(0.0, .millimeter),
        deltaY: .length(0.0, .millimeter),
        deltaZ: .length(1.0, .millimeter)
    )

    let feature = try #require(document.cadDocument.designGraph.nodes[featureID])
    guard case let .polySpline(polySpline) = feature.operation else {
        Issue.record("Expected a PolySpline feature.")
        return
    }
    let override = try #require(polySpline.controlPointOverrides.first)
    #expect(polySpline.controlPointOverrides.count == 1)
    #expect(override.patchID == 0)
    #expect(override.uIndex == 1)
    #expect(override.vIndex == 1)
    #expect(abs(override.point.x - controlPoint.point.x) <= 1.0e-12)
    #expect(abs(override.point.y - controlPoint.point.y) <= 1.0e-12)
    #expect(abs(override.point.z - (controlPoint.point.z + 0.001)) <= 1.0e-12)

    let measurement = try SelectionMeasurementService().measure(
        query: CADAgentMeasurementQuery(kind: .point, first: controlPoint.selectionReference),
        document: document
    )
    guard case .point(let measuredPoint) = measurement else {
        Issue.record("Expected moved interior control point measurement.")
        return
    }
    #expect(abs(measuredPoint.point.z - override.point.z) <= 1.0e-12)
}

@Test func surfaceControlPointReferenceWeightMutatesInteriorControlPointOverride() async throws {
    var document = DesignDocument.empty()

    let featureID = try document.createPolySplineSurface(
        name: "Weighted Interior Surface Reference Quad Surface",
        sourceMesh: designDocumentPolySplineQuadMesh()
    )
    let summary = try SurfaceSourceSummaryService().summarize(document: document)
    let controlPoint = try #require(
        summary.sources.first?.patches.first?.controlPoints.first { $0.uIndex == 1 && $0.vIndex == 1 }
    )

    try document.setSurfaceControlPointWeight(
        target: controlPoint.selectionReference,
        weight: .scalar(2.5)
    )

    let feature = try #require(document.cadDocument.designGraph.nodes[featureID])
    guard case let .polySpline(polySpline) = feature.operation else {
        Issue.record("Expected a PolySpline feature.")
        return
    }
    let override = try #require(polySpline.controlPointOverrides.first)
    #expect(polySpline.controlPointOverrides.count == 1)
    #expect(override.patchID == 0)
    #expect(override.uIndex == 1)
    #expect(override.vIndex == 1)
    #expect(override.weight == 2.5)
    #expect(abs(override.point.x - controlPoint.point.x) <= 1.0e-12)
    #expect(abs(override.point.y - controlPoint.point.y) <= 1.0e-12)
    #expect(abs(override.point.z - controlPoint.point.z) <= 1.0e-12)

    let updatedSummary = try SurfaceSourceSummaryService().summarize(document: document)
    let updatedPatch = try #require(updatedSummary.sources.first?.patches.first)
    let updatedControlPoint = try #require(
        updatedPatch.controlPoints.first { $0.uIndex == 1 && $0.vIndex == 1 }
    )
    #expect(updatedPatch.basis.isRational)
    #expect(updatedControlPoint.weight == 2.5)

    try document.moveSurfaceControlPoint(
        target: controlPoint.selectionReference,
        deltaX: .length(0.0, .millimeter),
        deltaY: .length(0.0, .millimeter),
        deltaZ: .length(1.0, .millimeter)
    )
    let movedFeature = try #require(document.cadDocument.designGraph.nodes[featureID])
    guard case let .polySpline(movedPolySpline) = movedFeature.operation else {
        Issue.record("Expected a moved PolySpline feature.")
        return
    }
    let movedOverride = try #require(movedPolySpline.controlPointOverrides.first)
    #expect(movedOverride.weight == 2.5)
    #expect(abs(movedOverride.point.z - (controlPoint.point.z + 0.001)) <= 1.0e-12)
}

@Test func polySplineSurfaceVertexMoveRejectsNonVertexTargets() async throws {
    var document = DesignDocument.empty()

    _ = try document.createPolySplineSurface(
        name: "Rejected Quad Surface",
        sourceMesh: designDocumentPolySplineQuadMesh()
    )
    let topology = try TopologySummaryService().summarize(document: document)
    let faceEntry = try #require(topology.entries.first {
        $0.kind == .face
            && $0.subshapeRole == "patch:0:face"
    })
    let target = try #require(faceEntry.selectionTarget())

    var caught: EditorError?
    do {
        try document.movePolySplineSurfaceVertex(
            target: target,
            deltaX: .length(0.0, .millimeter),
            deltaY: .length(0.0, .millimeter),
            deltaZ: .length(1.0, .millimeter)
        )
    } catch let error as EditorError {
        caught = error
    }

    #expect(caught?.code == .commandInvalid)
    #expect(caught?.message.contains("generated topology vertex") == true)
}

@Test func polySplineSurfaceVertexSlideMovesBoundaryVertexAlongPositiveU() async throws {
    var document = DesignDocument.empty()

    let featureID = try document.createPolySplineSurface(
        name: "Slide U Quad Surface",
        sourceMesh: designDocumentPolySplineQuadMesh()
    )
    let target = try polySplineVertexTarget(
        role: "patch:0:vertex:uMin:vMin",
        in: document
    )

    try document.slidePolySplineSurfaceVertices(
        targets: [target],
        direction: .positiveU,
        distance: .length(1.0, .millimeter)
    )

    let feature = try #require(document.cadDocument.designGraph.nodes[featureID])
    guard case let .polySpline(polySpline) = feature.operation else {
        Issue.record("Expected a PolySpline feature.")
        return
    }
    #expect(abs(polySpline.sourceMesh.positions[0].x - 0.001) <= 1.0e-12)
    #expect(abs(polySpline.sourceMesh.positions[0].y) <= 1.0e-12)
    #expect(abs(polySpline.sourceMesh.positions[0].z) <= 1.0e-12)
}

@Test func polySplineSurfaceVertexSlideMovesBoundaryVertexAlongPositiveV() async throws {
    var document = DesignDocument.empty()

    let featureID = try document.createPolySplineSurface(
        name: "Slide V Quad Surface",
        sourceMesh: designDocumentPolySplineQuadMesh()
    )
    let target = try polySplineVertexTarget(
        role: "patch:0:vertex:uMax:vMin",
        in: document
    )

    try document.slidePolySplineSurfaceVertices(
        targets: [target],
        direction: .positiveV,
        distance: .length(1.0, .millimeter)
    )

    let feature = try #require(document.cadDocument.designGraph.nodes[featureID])
    guard case let .polySpline(polySpline) = feature.operation else {
        Issue.record("Expected a PolySpline feature.")
        return
    }
    let length = sqrt((0.02 * 0.02) + (0.004 * 0.004))
    #expect(abs(polySpline.sourceMesh.positions[1].x - 0.02) <= 1.0e-12)
    #expect(abs(polySpline.sourceMesh.positions[1].y - (0.02 / length * 0.001)) <= 1.0e-12)
    #expect(abs(polySpline.sourceMesh.positions[1].z - (0.004 / length * 0.001)) <= 1.0e-12)
}

@Test func surfaceControlPointReferenceSlideMovesBoundaryVertexAlongPositiveV() async throws {
    var document = DesignDocument.empty()

    let featureID = try document.createPolySplineSurface(
        name: "Surface Reference Slide V Quad Surface",
        sourceMesh: designDocumentPolySplineQuadMesh()
    )
    let summary = try SurfaceSourceSummaryService().summarize(document: document)
    let source = try #require(summary.sources.first)
    let patch = try #require(source.patches.first)
    let controlVertex = try #require(patch.controlVertices.first { $0.role == "uMax:vMin" })

    try document.slideSurfaceControlPoints(
        targets: [controlVertex.selectionReference],
        direction: .positiveV,
        distance: .length(1.0, .millimeter)
    )

    let feature = try #require(document.cadDocument.designGraph.nodes[featureID])
    guard case let .polySpline(polySpline) = feature.operation else {
        Issue.record("Expected a PolySpline feature.")
        return
    }
    let length = sqrt((0.02 * 0.02) + (0.004 * 0.004))
    #expect(abs(polySpline.sourceMesh.positions[1].x - 0.02) <= 1.0e-12)
    #expect(abs(polySpline.sourceMesh.positions[1].y - (0.02 / length * 0.001)) <= 1.0e-12)
    #expect(abs(polySpline.sourceMesh.positions[1].z - (0.004 / length * 0.001)) <= 1.0e-12)
}

@Test func surfaceControlPointReferenceSlideMovesInteriorControlPointAlongPositiveU() async throws {
    var document = DesignDocument.empty()

    let featureID = try document.createPolySplineSurface(
        name: "Surface Reference Interior Slide U Quad Surface",
        sourceMesh: designDocumentPolySplineQuadMesh()
    )
    let summary = try SurfaceSourceSummaryService().summarize(document: document)
    let source = try #require(summary.sources.first)
    let patch = try #require(source.patches.first)
    let controlPoint = try #require(patch.controlPoints.first { $0.uIndex == 1 && $0.vIndex == 1 })
    let lowerUControlPoint = try #require(patch.controlPoints.first { $0.uIndex == 0 && $0.vIndex == 1 })
    let upperUControlPoint = try #require(patch.controlPoints.first { $0.uIndex == 2 && $0.vIndex == 1 })
    let hullDirection = Vector3D(
        x: upperUControlPoint.point.x - lowerUControlPoint.point.x,
        y: upperUControlPoint.point.y - lowerUControlPoint.point.y,
        z: upperUControlPoint.point.z - lowerUControlPoint.point.z
    )
    let unitU = try hullDirection.normalized(tolerance: ModelingTolerance.standard.distance)

    try document.slideSurfaceControlPoints(
        targets: [controlPoint.selectionReference],
        direction: .positiveU,
        distance: .length(1.0, .millimeter)
    )

    let feature = try #require(document.cadDocument.designGraph.nodes[featureID])
    guard case let .polySpline(polySpline) = feature.operation else {
        Issue.record("Expected a PolySpline feature.")
        return
    }
    let override = try #require(polySpline.controlPointOverrides.first)
    #expect(abs(override.point.x - (controlPoint.point.x + unitU.x * 0.001)) <= 1.0e-12)
    #expect(abs(override.point.y - (controlPoint.point.y + unitU.y * 0.001)) <= 1.0e-12)
    #expect(abs(override.point.z - (controlPoint.point.z + unitU.z * 0.001)) <= 1.0e-12)
}

@Test func surfaceControlPointReferenceSlideUsesOverrideAwareControlHullForInteriorControlPoint() async throws {
    var document = DesignDocument.empty()

    let featureID = try document.createPolySplineSurface(
        name: "Surface Reference Interior Slide Control Hull Surface",
        sourceMesh: designDocumentPolySplineQuadMesh()
    )
    let initialSummary = try SurfaceSourceSummaryService().summarize(document: document)
    let initialSource = try #require(initialSummary.sources.first)
    let initialPatch = try #require(initialSource.patches.first)
    let raisedControlPoint = try #require(initialPatch.controlPoints.first {
        $0.uIndex == 1 && $0.vIndex == 1
    })

    try document.moveSurfaceControlPoint(
        target: raisedControlPoint.selectionReference,
        deltaX: .length(0.0, .millimeter),
        deltaY: .length(0.0, .millimeter),
        deltaZ: .length(6.0, .millimeter)
    )

    let raisedSummary = try SurfaceSourceSummaryService().summarize(document: document)
    let raisedSource = try #require(raisedSummary.sources.first)
    let raisedPatch = try #require(raisedSource.patches.first)
    let slideControlPoint = try #require(raisedPatch.controlPoints.first {
        $0.uIndex == 2 && $0.vIndex == 1
    })
    let lowerUControlPoint = try #require(raisedPatch.controlPoints.first {
        $0.uIndex == 1 && $0.vIndex == 1
    })
    let upperUControlPoint = try #require(raisedPatch.controlPoints.first {
        $0.uIndex == 3 && $0.vIndex == 1
    })
    let hullDirection = Vector3D(
        x: upperUControlPoint.point.x - lowerUControlPoint.point.x,
        y: upperUControlPoint.point.y - lowerUControlPoint.point.y,
        z: upperUControlPoint.point.z - lowerUControlPoint.point.z
    )
    let unitU = try hullDirection.normalized(tolerance: ModelingTolerance.standard.distance)

    try document.slideSurfaceControlPoints(
        targets: [slideControlPoint.selectionReference],
        direction: .positiveU,
        distance: .length(1.0, .millimeter)
    )

    let feature = try #require(document.cadDocument.designGraph.nodes[featureID])
    guard case let .polySpline(polySpline) = feature.operation else {
        Issue.record("Expected a PolySpline feature.")
        return
    }
    let override = try #require(polySpline.controlPointOverrides.first {
        $0.uIndex == 2 && $0.vIndex == 1
    })
    #expect(abs(override.point.x - (slideControlPoint.point.x + unitU.x * 0.001)) <= 1.0e-12)
    #expect(abs(override.point.y - (slideControlPoint.point.y + unitU.y * 0.001)) <= 1.0e-12)
    #expect(abs(override.point.z - (slideControlPoint.point.z + unitU.z * 0.001)) <= 1.0e-12)
}

@Test func polySplineSurfaceVertexSlideMovesBoundaryVertexAlongNormal() async throws {
    var document = DesignDocument.empty()

    let featureID = try document.createPolySplineSurface(
        name: "Slide Normal Quad Surface",
        sourceMesh: designDocumentPolySplineQuadMesh()
    )
    let target = try polySplineVertexTarget(
        role: "patch:0:vertex:uMin:vMin",
        in: document
    )

    try document.slidePolySplineSurfaceVertices(
        targets: [target],
        direction: .normal,
        distance: .length(1.0, .millimeter)
    )

    let feature = try #require(document.cadDocument.designGraph.nodes[featureID])
    guard case let .polySpline(polySpline) = feature.operation else {
        Issue.record("Expected a PolySpline feature.")
        return
    }
    #expect(abs(polySpline.sourceMesh.positions[0].x) <= 1.0e-12)
    #expect(abs(polySpline.sourceMesh.positions[0].y) <= 1.0e-12)
    #expect(abs(polySpline.sourceMesh.positions[0].z - 0.001) <= 1.0e-12)
}

@Test func polySplineSurfaceVertexSlideRejectsDuplicateSourceTargets() async throws {
    var document = DesignDocument.empty()

    _ = try document.createPolySplineSurface(
        name: "Rejected Slide Quad Surface",
        sourceMesh: designDocumentPolySplineQuadMesh()
    )
    let target = try polySplineVertexTarget(
        role: "patch:0:vertex:uMin:vMin",
        in: document
    )

    var caught: EditorError?
    do {
        try document.slidePolySplineSurfaceVertices(
            targets: [target, target],
            direction: .positiveU,
            distance: .length(1.0, .millimeter)
        )
    } catch let error as EditorError {
        caught = error
    }

    #expect(caught?.code == .commandInvalid)
    #expect(caught?.message.contains("duplicate targets") == true)
}

@Test func polySplineSurfaceCreatesPlanarUnmergedPatchNetworkTypedSheetObject() async throws {
    var document = DesignDocument.empty()

    let featureID = try document.createPolySplineSurface(
        name: "Planar Patch Network",
        sourceMesh: designDocumentPolySplinePatchNetworkMesh(centerZ: 0.0),
        options: PolySplineOptions(mergePatches: false)
    )

    let feature = try #require(document.cadDocument.designGraph.nodes[featureID])
    guard case let .polySpline(polySpline) = feature.operation else {
        Issue.record("Expected a PolySpline feature.")
        return
    }
    #expect(polySpline.options.mergePatches == false)
    #expect(feature.outputs == [FeatureOutput(role: .sheet)])
    let node = try #require(document.productMetadata.sceneNodes.values.first {
        $0.reference?.featureID == featureID
    })
    #expect(node.object?.typeID == .polySpline)
    #expect(node.object?.geometryRole == .surface)
    #expect(node.object?.properties["patch.count"] == .integer(2))
    #expect(node.object?.properties["control.point.u"] == .integer(4))
    #expect(node.object?.properties["control.point.v"] == .integer(4))
    #expect(node.object?.properties["merge.patches"] == .boolean(false))
    #expect(node.object?.properties["interpolate.boundary"] == .boolean(true))
}

@Test func polySplineMeshAnalysisServiceReportsPreflightDiagnostics() async throws {
    let result = PolySplineMeshAnalysisService().analyze(
        sourceMesh: designDocumentPolySplineQuadMesh(),
        options: PolySplineOptions(roundedCorners: true)
    )

    #expect(!result.isSupported)
    #expect(result.candidateKind == .singleQuad)
    #expect(result.supportedPatchCount == 1)
    #expect(result.candidatePatchCount == 1)
    #expect(result.patchGraph?.candidates.count == 1)
    #expect(result.patchGraph?.partition?.selectedCandidateIDs == [0])
    #expect(result.errors.contains { $0.code == .unsupportedRoundedCorners })
}

@Test func polySplineMeshAnalysisServiceReportsPatchGraphCandidates() async throws {
    let result = PolySplineMeshAnalysisService().analyze(
        sourceMesh: designDocumentPolySplinePatchNetworkMesh()
    )

    #expect(!result.isSupported)
    #expect(result.candidateKind == .quadPatchGraph)
    #expect(result.supportedPatchCount == 0)
    #expect(result.candidatePatchCount == 3)
    #expect(result.patchGraph?.ambiguousTriangleIndices == [0, 3])
    #expect(result.patchGraph?.partition?.isComplete == true)
    #expect(result.patchGraph?.partition?.selectedCandidateIDs == [0, 2])
    #expect(result.patchGraph?.partition?.rejectedCandidateIDs == [1])
    let adjacency = try #require(result.patchGraph?.selectedAdjacencies.first)
    #expect(result.patchGraph?.selectedAdjacencies.count == 1)
    #expect(adjacency.firstCandidateID == 0)
    #expect(adjacency.secondCandidateID == 2)
    #expect(adjacency.sharedVertexIndices == [1, 4])
    #expect(adjacency.continuityLevel == .positional)
    #expect(adjacency.requiresCurvatureContinuitySolve)
    #expect(result.diagnostics.contains { $0.code == .patchGraphIdentified })
    #expect(result.diagnostics.contains { $0.code == .patchGraphPartitioned })
    #expect(result.diagnostics.contains { $0.code == .patchAdjacencyIdentified })
    #expect(result.diagnostics.contains { $0.code == .patchTangentPlaneDiscontinuity })
    #expect(result.diagnostics.contains { $0.code == .patchCurvatureContinuityUnresolved })
}

@Test func polySplineMeshAnalysisServiceSupportsPlanarUnmergedPatchNetwork() async throws {
    let result = PolySplineMeshAnalysisService().analyze(
        sourceMesh: designDocumentPolySplinePatchNetworkMesh(centerZ: 0.0),
        options: PolySplineOptions(mergePatches: false)
    )

    #expect(result.isSupported)
    #expect(result.candidateKind == .quadPatchGraph)
    #expect(result.supportedPatchCount == 2)
    #expect(result.candidatePatchCount == 3)
    #expect(result.patchGraph?.partition?.selectedCandidateIDs == [0, 2])
    #expect(result.patchGraph?.selectedAdjacencies.count == 1)
    #expect(result.patchGraph?.selectedAdjacencies.first?.continuityLevel == .tangentPlane)
    #expect(result.patchGraph?.selectedAdjacencies.first?.requiresCurvatureContinuitySolve == false)
    #expect(result.diagnostics.contains { $0.code == .planarPatchNetworkSupported })
    #expect(!result.diagnostics.contains { $0.code == .patchCurvatureContinuityUnresolved })
    #expect(result.errors.isEmpty)
}

@Test func polySplineSurfaceRejectsUnsupportedOptionsBeforeMutation() async throws {
    var document = DesignDocument.empty()
    var caught: EditorError?

    do {
        _ = try document.createPolySplineSurface(
            name: "Rounded Surface",
            sourceMesh: designDocumentPolySplineQuadMesh(),
            options: PolySplineOptions(roundedCorners: true)
        )
    } catch let error as EditorError {
        caught = error
    }

    #expect(caught?.code == .commandInvalid)
    #expect(caught?.message.contains("rounded-corner") == true)
    #expect(document.cadDocument.designGraph.order.isEmpty)
    #expect(document.productMetadata.sceneNodes.values.allSatisfy { $0.reference == nil })
}

@Test func sketchObjectsReceiveTypedProperties() async throws {
    var document = DesignDocument.empty()

    let featureID = try document.createRectangleSketch(
        name: "Profile",
        plane: .xy,
        width: .length(2.0, .meter),
        height: .length(3.0, .meter)
    )

    let node = try #require(document.productMetadata.sceneNodes.values.first {
        $0.reference?.featureID == featureID
    })
    #expect(node.object?.typeID == .rectangle)
    #expect(node.object?.properties["size.x"] == .length(2.0))
    #expect(node.object?.properties["size.y"] == .length(3.0))
}

@Test func objectPropertyMutationUsesObjectTypeSchema() async throws {
    var document = DesignDocument.empty()

    let featureID = try document.createRectangleSketch(
        name: "Editable Profile",
        plane: .xy,
        width: .length(1.0, .meter),
        height: .length(1.0, .meter)
    )

    let node = try #require(document.productMetadata.sceneNodes.values.first {
        $0.reference?.featureID == featureID
    })
    try document.setSceneNodeObjectProperty(
        id: node.id,
        propertyID: "extrusion",
        value: .length(0.5)
    )
    let editedNode = try #require(document.productMetadata.sceneNodes[node.id])
    #expect(editedNode.object?.properties["extrusion"] == .length(0.5))

    do {
        try document.setSceneNodeObjectProperty(
            id: node.id,
            propertyID: "unknown",
            value: .length(1.0)
        )
        Issue.record("Undefined object properties must be rejected.")
    } catch {
        #expect(error is DocumentValidationError)
    }
}

@Test func customObjectRegistrySurvivesNonPropertyMutations() async throws {
    let customTypeID: ObjectTypeID = "custom.panel"
    let registry = try ObjectTypeRegistry(
        definitions: ObjectTypeCatalog.builtInDefinitions + [
            ObjectTypeDefinition(
                id: customTypeID,
                title: "Panel",
                systemImage: "rectangle",
                representation: .twoDimensional,
                category: .sketch,
                geometryRole: .sketchProfile,
                properties: [
                    ObjectPropertyDefinition(
                        id: "panel.thickness",
                        title: "Thickness",
                        group: "Shape",
                        valueKind: .length,
                        defaultValue: .length(0.02),
                        inspectorControl: .textFieldAndSlider,
                        renderBinding: "panel.thickness",
                        numericRange: ObjectPropertyDefinition.NumericRange(
                            lowerBound: 0.0,
                            upperBound: 1.0
                        )
                    ),
                ]
            ),
        ]
    )
    var document = DesignDocument.empty()
    let featureID = try document.createRectangleSketch(
        name: "Custom Panel Source",
        plane: .xy,
        width: .length(1.0, .meter),
        height: .length(1.0, .meter),
        objectRegistry: registry
    )
    var node = try #require(document.productMetadata.sceneNodes.values.first {
        $0.reference?.featureID == featureID
    })
    node.object = .sketch(
        featureID: featureID,
        typeID: customTypeID,
        properties: ObjectPropertySet(values: ["panel.thickness": .length(0.04)]),
        objectRegistry: registry
    )
    document.productMetadata.sceneNodes[node.id] = node

    try document.validate(objectRegistry: registry)
    try document.setSceneNodeVisibility(
        id: node.id,
        isVisible: false,
        objectRegistry: registry
    )

    #expect(document.productMetadata.sceneNodes[node.id]?.isVisible == false)
    #expect(document.productMetadata.sceneNodes[node.id]?.object?.typeID == customTypeID)
}

@Test func customObjectRegistryParticipatesInEvaluationValidation() async throws {
    let customTypeID: ObjectTypeID = "custom.panel"
    let registry = try ObjectTypeRegistry(
        definitions: ObjectTypeCatalog.builtInDefinitions + [
            ObjectTypeDefinition(
                id: customTypeID,
                title: "Panel",
                systemImage: "rectangle",
                representation: .twoDimensional,
                category: .sketch,
                geometryRole: .sketchProfile,
                properties: [
                    ObjectPropertyDefinition(
                        id: "panel.thickness",
                        title: "Thickness",
                        group: "Shape",
                        valueKind: .length,
                        defaultValue: .length(0.02),
                        inspectorControl: .textFieldAndSlider,
                        renderBinding: "panel.thickness"
                    ),
                ]
            ),
        ]
    )
    var document = DesignDocument.empty()
    let featureID = try document.createRectangleSketch(
        name: "Custom Panel Source",
        plane: .xy,
        width: .length(1.0, .meter),
        height: .length(1.0, .meter),
        objectRegistry: registry
    )
    var node = try #require(document.productMetadata.sceneNodes.values.first {
        $0.reference?.featureID == featureID
    })
    node.object = .sketch(
        featureID: featureID,
        typeID: customTypeID,
        properties: ObjectPropertySet(values: ["panel.thickness": .length(0.04)]),
        objectRegistry: registry
    )
    document.productMetadata.sceneNodes[node.id] = node
    let store = CADDocumentStore(document: document, objectRegistry: registry)

    store.evaluateCurrentDocument()

    #expect(store.evaluationStatus == .valid)
}

@Test func objectTypeValidationRejectsMismatchedCategory() async throws {
    var document = DesignDocument.empty()
    let featureID = try document.createRectangleSketch(
        name: "Profile",
        plane: .xy,
        width: .length(1.0, .meter),
        height: .length(1.0, .meter)
    )
    var node = try #require(document.productMetadata.sceneNodes.values.first {
        $0.reference?.featureID == featureID
    })
    node.object = ObjectDescriptor(
        category: .sketch,
        geometryRole: .solid,
        typeID: .cube,
        sourceFeatureID: featureID
    )
    document.productMetadata.sceneNodes[node.id] = node

    do {
        try document.validate(objectRegistry: .builtIn)
        Issue.record("Validation should reject object type category mismatch.")
    } catch {
        #expect(error is DocumentValidationError)
    }
}

@Test func objectSizePropertyMutationUpdatesCubeSourceGeometry() async throws {
    var document = DesignDocument.empty()
    try document.createExtrudedRectangle(
        name: "Block",
        plane: .xy,
        width: .length(1.0, .meter),
        height: .length(1.0, .meter),
        depth: .length(0.5, .meter),
        direction: .normal
    )
    let bodyNode = try #require(document.productMetadata.sceneNodes.values.first {
        $0.reference?.kind == .body
    })

    try document.setSceneNodeObjectProperty(
        id: bodyNode.id,
        propertyID: "size.x",
        value: .length(2.0)
    )

    let editedBodyNode = try #require(document.productMetadata.sceneNodes[bodyNode.id])
    #expect(editedBodyNode.object?.properties["size.x"] == .length(2.0))
    let bodyFeatureID = try #require(editedBodyNode.reference?.featureID)
    let bodyFeature = try #require(document.cadDocument.designGraph.nodes[bodyFeatureID])
    guard case let .extrude(extrude) = bodyFeature.operation else {
        Issue.record("Expected an extrude feature.")
        return
    }
    let profileFeature = try #require(document.cadDocument.designGraph.nodes[extrude.profile.featureID])
    guard case let .sketch(sketch) = profileFeature.operation else {
        Issue.record("Expected a sketch profile.")
        return
    }
    let bounds = try sketchBounds(sketch, parameters: document.cadDocument.parameters)

    #expect(abs(bounds.width - 2.0) < 0.000_000_000_001)
    #expect(abs(bounds.height - 1.0) < 0.000_000_000_001)
}

@Test func objectDimensionCommandUpdatesBoxSourceGeometryFromSelectionTarget() async throws {
    var document = DesignDocument.empty()
    try document.createExtrudedRectangle(
        name: "Dimensioned Block",
        plane: .xy,
        width: .length(1.0, .meter),
        height: .length(1.5, .meter),
        depth: .length(0.5, .meter),
        direction: .normal
    )
    let bodyNode = try #require(document.productMetadata.sceneNodes.values.first {
        $0.reference?.kind == .body
    })

    try document.setObjectDimension(
        target: SelectionTarget(sceneNodeID: bodyNode.id),
        kind: .sizeX,
        value: .length(2.0, .meter)
    )
    try document.setObjectDimension(
        target: SelectionTarget(sceneNodeID: bodyNode.id, component: .face(.bodyFaceTop)),
        kind: .sizeY,
        value: .length(0.75, .meter)
    )

    let editedBodyNode = try #require(document.productMetadata.sceneNodes[bodyNode.id])
    #expect(editedBodyNode.object?.properties["size.x"] == .length(2.0))
    #expect(editedBodyNode.object?.properties["size.y"] == .length(0.75))
    let bodyFeatureID = try #require(editedBodyNode.reference?.featureID)
    let bodyFeature = try #require(document.cadDocument.designGraph.nodes[bodyFeatureID])
    guard case let .extrude(extrude) = bodyFeature.operation else {
        Issue.record("Expected an extrude feature.")
        return
    }
    let depth = try resolvedLength(extrude.distance, parameters: document.cadDocument.parameters)
    #expect(abs(depth - 0.75) < 0.000_000_000_001)
    let profileFeature = try #require(document.cadDocument.designGraph.nodes[extrude.profile.featureID])
    guard case let .sketch(sketch) = profileFeature.operation else {
        Issue.record("Expected a sketch profile.")
        return
    }
    let bounds = try sketchBounds(sketch, parameters: document.cadDocument.parameters)
    #expect(abs(bounds.width - 2.0) < 0.000_000_000_001)
    #expect(abs(bounds.height - 1.5) < 0.000_000_000_001)
}

@Test func objectDimensionCommandUpdatesCylinderSourceGeometryFromFaceTarget() async throws {
    var document = DesignDocument.empty()
    try document.createExtrudedCircle(
        name: "Dimensioned Cylinder",
        plane: .xy,
        center: SketchPoint(
            x: .length(0.0, .meter),
            y: .length(0.0, .meter)
        ),
        radius: .length(0.5, .meter),
        depth: .length(1.0, .meter),
        direction: .normal
    )
    let bodyNode = try #require(document.productMetadata.sceneNodes.values.first {
        $0.reference?.kind == .body && $0.object?.typeID == .cylinder
    })

    try document.setObjectDimension(
        target: SelectionTarget(sceneNodeID: bodyNode.id, component: .face(.bodyFaceSide)),
        kind: .diameter,
        value: .length(2.0, .meter)
    )
    try document.setObjectDimension(
        target: SelectionTarget(sceneNodeID: bodyNode.id),
        kind: .sizeY,
        value: .length(2.5, .meter)
    )

    let editedBodyNode = try #require(document.productMetadata.sceneNodes[bodyNode.id])
    #expect(editedBodyNode.object?.properties["radius"] == .length(1.0))
    #expect(editedBodyNode.object?.properties["size.x"] == .length(2.0))
    #expect(editedBodyNode.object?.properties["size.y"] == .length(2.5))
    #expect(editedBodyNode.object?.properties["size.z"] == .length(2.0))
    let bodyFeatureID = try #require(editedBodyNode.reference?.featureID)
    let bodyFeature = try #require(document.cadDocument.designGraph.nodes[bodyFeatureID])
    guard case let .extrude(extrude) = bodyFeature.operation else {
        Issue.record("Expected an extrude feature.")
        return
    }
    let depth = try resolvedLength(extrude.distance, parameters: document.cadDocument.parameters)
    #expect(abs(depth - 2.5) < 0.000_000_000_001)
    let profileFeature = try #require(document.cadDocument.designGraph.nodes[extrude.profile.featureID])
    guard case let .sketch(sketch) = profileFeature.operation else {
        Issue.record("Expected a sketch profile.")
        return
    }
    let circle = try #require(sketch.entities.values.compactMap { entity -> SketchCircle? in
        if case .circle(let circle) = entity {
            return circle
        }
        return nil
    }.first)
    let radius = try resolvedLength(circle.radius, parameters: document.cadDocument.parameters)
    #expect(abs(radius - 1.0) < 0.000_000_000_001)
}

@Test func objectDimensionSummaryListsBoxCandidatesFromObjectTarget() async throws {
    var document = DesignDocument.empty()
    try document.createExtrudedRectangle(
        name: "Dimension Summary Box",
        plane: .xy,
        width: .length(1.0, .meter),
        height: .length(1.5, .meter),
        depth: .length(0.5, .meter),
        direction: .normal
    )
    let bodyNode = try #require(document.productMetadata.sceneNodes.values.first {
        $0.reference?.kind == .body
    })

    let summary = try ObjectDimensionSummaryService().summarize(
        document: document,
        targets: [SelectionTarget(sceneNodeID: bodyNode.id)]
    )

    #expect(summary.counts.targetCount == 1)
    #expect(summary.counts.entryCount == 3)
    #expect(summary.entries.map(\.kind) == [.sizeX, .sizeY, .sizeZ])
    #expect(summary.entries.allSatisfy { $0.sourceKind == .box })
    #expect(summary.entries.first?.isPrimaryForTarget == true)
    let values = Dictionary(uniqueKeysWithValues: summary.entries.map { ($0.kind, $0.resolvedMeters) })
    #expect(abs((values[.sizeX] ?? 0.0) - 1.0) < 0.000_000_000_001)
    #expect(abs((values[.sizeY] ?? 0.0) - 0.5) < 0.000_000_000_001)
    #expect(abs((values[.sizeZ] ?? 0.0) - 1.5) < 0.000_000_000_001)
    #expect(summary.entries.first { $0.kind == .sizeY }?.sourceExpression == .length(0.5, .meter))
}

@Test func objectDimensionSummaryInfersPrimaryDimensionFromGeneratedBoxFace() async throws {
    var document = DesignDocument.empty()
    try document.createExtrudedRectangle(
        name: "Dimension Summary Generated Face Box",
        plane: .xy,
        width: .length(1.0, .meter),
        height: .length(1.5, .meter),
        depth: .length(0.5, .meter),
        direction: .normal
    )
    let bodyNode = try #require(document.productMetadata.sceneNodes.values.first {
        $0.reference?.kind == .body
    })
    let resolver = GeneratedTopologySelectionResolver()
    let requestedFaces: [(face: BodyFace, expectedKind: ObjectDimensionKind)] = [
        (.right, .sizeX),
        (.front, .sizeY),
        (.top, .sizeZ),
    ]

    for requestedFace in requestedFaces {
        let componentID = try #require(
            try resolver.componentID(
                for: bodyNode.id,
                bodyFace: requestedFace.face,
                in: document
            )
        )
        let target = SelectionTarget(sceneNodeID: bodyNode.id, component: .face(componentID))

        let summary = try ObjectDimensionSummaryService().summarize(
            document: document,
            targets: [target]
        )

        #expect(summary.counts.targetCount == 1)
        #expect(summary.counts.entryCount == 3)
        let primary = try #require(summary.entries.first { $0.isPrimaryForTarget })
        #expect(primary.kind == requestedFace.expectedKind)
        #expect(primary.target == target)
    }
}

@MainActor
@Test func objectDimensionSummaryExpandsIndependentCopyOutputRootToBodyDescendants() async throws {
    let session = EditorSession()
    _ = try #require(session.createDefaultExtrudedRectangle())
    let bodyFeatureID = try #require(session.document.cadDocument.designGraph.order.last)
    let bodySceneNodeID = try #require(
        session.document.productMetadata.sceneNodes.first { _, node in
            node.reference == .body(bodyFeatureID)
        }?.key
    )
    _ = try session.execute(
        .createComponentDefinition(
            name: "Dimension Summary Clone Source",
            rootSceneNodeIDs: [bodySceneNodeID]
        )
    )
    let definition = try #require(session.document.productMetadata.componentDefinitions.values.first {
        $0.name == "Dimension Summary Clone Source"
    })
    _ = try session.execute(
        .createPatternArray(
            name: "Dimension Summary Clone Array",
            definitionID: definition.id,
            distribution: .rectangular(RectangularPatternArray(
                firstAxis: PatternArrayLinearAxis(
                    direction: .unitX,
                    distance: .length(8.0, .millimeter),
                    copyCount: 2
                )
            )),
            outputMode: .independentCopy
        )
    )
    let source = try #require(session.document.productMetadata.patternArrays.values.first {
        $0.name == "Dimension Summary Clone Array"
    })
    let outputSceneNodeID = try #require(source.outputSceneNodeIDs.first)

    let summary = try ObjectDimensionSummaryService().summarize(
        document: session.document,
        targets: [SelectionTarget(sceneNodeID: outputSceneNodeID)]
    )
    let outputFeatureIDDescriptions = Set(source.outputFeatureIDs.map(\.description))

    #expect(summary.counts.targetCount == 1)
    #expect(summary.counts.entryCount == 3)
    #expect(summary.entries.map(\.kind) == [.sizeX, .sizeY, .sizeZ])
    #expect(summary.entries.allSatisfy { outputFeatureIDDescriptions.contains($0.sourceFeatureID) })
    #expect(summary.entries.allSatisfy { $0.target.sceneNodeID != outputSceneNodeID })
}

@Test func objectDimensionSummaryListsCylinderCandidatesFromFaceTarget() async throws {
    var document = DesignDocument.empty()
    try document.createExtrudedCircle(
        name: "Dimension Summary Cylinder",
        plane: .xy,
        center: SketchPoint(
            x: .length(0.0, .meter),
            y: .length(0.0, .meter)
        ),
        radius: .length(0.5, .meter),
        depth: .length(1.0, .meter),
        direction: .normal
    )
    let bodyNode = try #require(document.productMetadata.sceneNodes.values.first {
        $0.reference?.kind == .body && $0.object?.typeID == .cylinder
    })

    let summary = try ObjectDimensionSummaryService().summarize(
        document: document,
        targets: [
            SelectionTarget(
                sceneNodeID: bodyNode.id,
                component: .face(.bodyFaceSide)
            ),
        ]
    )

    #expect(summary.counts.targetCount == 1)
    #expect(summary.counts.entryCount == 3)
    #expect(summary.entries.map(\.kind) == [.diameter, .radius, .sizeY])
    #expect(summary.entries.allSatisfy { $0.sourceKind == .cylinder })
    let primary = try #require(summary.entries.first { $0.isPrimaryForTarget })
    #expect(primary.kind == .diameter)
    let values = Dictionary(uniqueKeysWithValues: summary.entries.map { ($0.kind, $0.resolvedMeters) })
    #expect(abs((values[.diameter] ?? 0.0) - 1.0) < 0.000_000_000_001)
    #expect(abs((values[.radius] ?? 0.0) - 0.5) < 0.000_000_000_001)
    #expect(abs((values[.sizeY] ?? 0.0) - 1.0) < 0.000_000_000_001)
    #expect(summary.entries.first { $0.kind == .radius }?.sourceExpression == .length(0.5, .meter))
    #expect(summary.entries.first { $0.kind == .sizeY }?.sourceExpression == .length(1.0, .meter))
}

@Test func objectDimensionSummaryInfersPrimaryDimensionFromGeneratedCylinderFace() async throws {
    var document = DesignDocument.empty()
    try document.createExtrudedCircle(
        name: "Dimension Summary Generated Face Cylinder",
        plane: .xy,
        center: SketchPoint(
            x: .length(0.0, .meter),
            y: .length(0.0, .meter)
        ),
        radius: .length(0.5, .meter),
        depth: .length(1.0, .meter),
        direction: .normal
    )
    let bodyNode = try #require(document.productMetadata.sceneNodes.values.first {
        $0.reference?.kind == .body && $0.object?.typeID == .cylinder
    })
    let resolver = GeneratedTopologySelectionResolver()
    let requestedFaces: [(face: BodyFace, expectedKind: ObjectDimensionKind)] = [
        (.side, .diameter),
        (.front, .sizeY),
    ]

    for requestedFace in requestedFaces {
        let componentID = try #require(
            try resolver.componentID(
                for: bodyNode.id,
                bodyFace: requestedFace.face,
                in: document
            )
        )
        let target = SelectionTarget(sceneNodeID: bodyNode.id, component: .face(componentID))

        let summary = try ObjectDimensionSummaryService().summarize(
            document: document,
            targets: [target]
        )

        #expect(summary.counts.targetCount == 1)
        #expect(summary.counts.entryCount == 3)
        let primary = try #require(summary.entries.first { $0.isPrimaryForTarget })
        #expect(primary.kind == requestedFace.expectedKind)
        #expect(primary.target == target)
    }
}

@Test func objectDimensionSummaryListsDepthCandidateFromGeneratedEdgeTarget() async throws {
    var document = DesignDocument.empty()
    try document.createExtrudedRectangle(
        name: "Dimension Summary Edge Box",
        plane: .xy,
        width: .length(1.0, .meter),
        height: .length(1.5, .meter),
        depth: .length(0.5, .meter),
        direction: .normal
    )
    let topology = try TopologySummaryService().summarize(document: document)
    let depthEdge = try #require(generatedDepthEdge(in: topology))
    let target = try #require(depthEdge.selectionTarget())

    let summary = try ObjectDimensionSummaryService().summarize(
        document: document,
        targets: [target]
    )

    #expect(summary.counts.targetCount == 1)
    #expect(summary.counts.entryCount == 3)
    #expect(summary.entries.map(\.kind) == [.sizeX, .sizeY, .sizeZ])
    #expect(summary.entries.allSatisfy { $0.sourceKind == .box })
    let primary = try #require(summary.entries.first { $0.isPrimaryForTarget })
    #expect(primary.kind == .sizeY)
    #expect(primary.target == target)
    let values = Dictionary(uniqueKeysWithValues: summary.entries.map { ($0.kind, $0.resolvedMeters) })
    #expect(abs((values[.sizeY] ?? 0.0) - 0.5) < 0.000_000_000_001)
}

@Test func objectDimensionSummaryListsFacePairDistanceCandidateFromGeneratedFaces() async throws {
    var document = DesignDocument.empty()
    try document.createExtrudedRectangle(
        name: "Dimension Summary Face Pair Box",
        plane: .xy,
        width: .length(1.0, .meter),
        height: .length(1.5, .meter),
        depth: .length(0.5, .meter),
        direction: .normal
    )
    let targets = try opposingGeneratedFaceTargets(in: document)

    let summary = try ObjectDimensionSummaryService().summarize(
        document: document,
        targets: [targets.first, targets.second]
    )

    #expect(summary.counts.targetCount == 2)
    #expect(summary.counts.entryCount == 1)
    let entry = try #require(summary.entries.first)
    #expect(entry.kind == .sizeY)
    #expect(entry.label == "Face Distance")
    #expect(entry.sourceKind == .box)
    #expect(entry.isPrimaryForTarget)
    #expect(entry.target == targets.first)
    #expect(entry.sourceExpression == .length(0.5, .meter))
    #expect(abs(entry.resolvedMeters - 0.5) < 0.000_000_000_001)

    try document.setObjectDimension(
        target: entry.target,
        kind: entry.kind,
        value: .length(0.75, .meter)
    )
    let bodyNode = try #require(document.productMetadata.sceneNodes[entry.target.sceneNodeID])
    #expect(bodyNode.object?.properties["size.y"] == .length(0.75))
}

@Test func objectDimensionCommandUpdatesDepthFromGeneratedEdgeTarget() async throws {
    var document = DesignDocument.empty()
    try document.createExtrudedRectangle(
        name: "Dimensioned Edge Box",
        plane: .xy,
        width: .length(1.0, .meter),
        height: .length(1.5, .meter),
        depth: .length(0.5, .meter),
        direction: .normal
    )
    let topology = try TopologySummaryService().summarize(document: document)
    let depthEdge = try #require(generatedDepthEdge(in: topology))
    let target = try #require(depthEdge.selectionTarget())

    try document.setObjectDimension(
        target: target,
        kind: .sizeY,
        value: .length(0.75, .meter)
    )

    let bodyNode = try #require(document.productMetadata.sceneNodes[target.sceneNodeID])
    #expect(bodyNode.object?.properties["size.y"] == .length(0.75))
    let bodyFeatureID = try #require(bodyNode.reference?.featureID)
    let bodyFeature = try #require(document.cadDocument.designGraph.nodes[bodyFeatureID])
    guard case let .extrude(extrude) = bodyFeature.operation else {
        Issue.record("Expected an extrude feature.")
        return
    }
    let depth = try resolvedLength(extrude.distance, parameters: document.cadDocument.parameters)
    #expect(abs(depth - 0.75) < 0.000_000_000_001)
}

@Test func sketchExtrusionPropertyCreatesAndRemovesGeneratedBody() async throws {
    var document = DesignDocument.empty()
    let featureID = try document.createRectangleSketch(
        name: "Panel",
        plane: .xy,
        width: .length(1.0, .meter),
        height: .length(2.0, .meter)
    )
    let sketchNode = try #require(document.productMetadata.sceneNodes.values.first {
        $0.reference?.featureID == featureID
    })

    try document.setSceneNodeObjectProperty(
        id: sketchNode.id,
        propertyID: "extrusion",
        value: .length(0.25)
    )

    let bodyNode = try #require(document.productMetadata.sceneNodes.values.first {
        $0.reference?.kind == .body && $0.object?.sourceSection?.profileReference?.featureID == featureID
    })
    #expect(document.cadDocument.designGraph.order.count == 2)
    #expect(bodyNode.name == "Panel Extrusion")
    #expect(bodyNode.object?.typeID == .cube)
    let bodyFeatureID = try #require(bodyNode.reference?.featureID)
    let bodyFeature = try #require(document.cadDocument.designGraph.nodes[bodyFeatureID])
    guard case let .extrude(extrude) = bodyFeature.operation else {
        Issue.record("Expected generated extrusion body.")
        return
    }
    let distance = try resolvedLength(extrude.distance, parameters: document.cadDocument.parameters)
    #expect(abs(distance - 0.25) < 0.000_000_000_001)

    try document.setSceneNodeObjectProperty(
        id: sketchNode.id,
        propertyID: "extrusion",
        value: .length(0.0)
    )

    #expect(document.cadDocument.designGraph.order == [featureID])
    #expect(!document.productMetadata.sceneNodes.values.contains {
        $0.reference?.kind == .body && $0.object?.sourceSection?.profileReference?.featureID == featureID
    })
}

@Test func productMetadataRoundTripsThroughProductPackage() async throws {
    let temporaryDirectory = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(
        at: temporaryDirectory,
        withIntermediateDirectories: true
    )
    defer {
        do {
            try FileManager.default.removeItem(at: temporaryDirectory)
        } catch {
            Issue.record("Failed to remove temporary directory: \(error)")
        }
    }

    let material = Material(
        name: "Default",
        baseColor: ColorRGBA(r: 0.2, g: 0.4, b: 0.8, a: 1.0),
        metallic: 0.0,
        roughness: 0.45,
        opacity: 1.0
    )
    let validationRule = ValidationRule(
        name: "Generic geometry readiness",
        category: .geometry,
        severity: .warning
    )
    let exportPreset = ExportPreset(
        name: "Print STL",
        format: .stl,
        outputUnit: .millimeter,
        validationRuleIDs: [validationRule.id]
    )
    var metadata = ProductMetadata.empty()
    metadata.materialLibrary = MaterialLibrary(
        materials: [material.id: material],
        defaultMaterialID: material.id
    )
    metadata.validationRules = [validationRule.id: validationRule]
    metadata.exportPresets = [exportPreset.id: exportPreset]
    metadata.templateDefaults = TemplateDefaults(
        displayUnit: .centimeter,
        ruler: .standard(for: .centimeter),
        validationRuleIDs: [validationRule.id],
        exportPresetIDs: [exportPreset.id],
        defaultMaterialID: material.id
    )

    var document = DesignDocument.empty(named: "Product Metadata")
    document.setDisplayUnit(.centimeter)
    document.productMetadata = metadata

    let url = temporaryDirectory.appendingPathComponent("product-metadata.swcad")
    let service = DocumentFileService()
    try service.save(document, to: url)
    let loaded = try service.load(from: url)

    #expect(loaded.displayUnit == .centimeter)
    #expect(loaded.ruler == .standard(for: .centimeter))
    #expect(loaded.productMetadata == metadata)
}

@Test func legacySwiftCADPackageLoadsWithDefaultProductMetadata() async throws {
    let temporaryDirectory = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(
        at: temporaryDirectory,
        withIntermediateDirectories: true
    )
    defer {
        do {
            try FileManager.default.removeItem(at: temporaryDirectory)
        } catch {
            Issue.record("Failed to remove temporary directory: \(error)")
        }
    }

    let url = temporaryDirectory.appendingPathComponent("legacy.swcad")
    let sourceDocument = DesignDocument.empty(named: "Legacy")
    try CADPipeline().save(sourceDocument.cadDocument, to: url)

    let loaded = try DocumentFileService().load(from: url)

    #expect(loaded.cadDocument.metadata.name == "Legacy")
    #expect(loaded.displayUnit == .millimeter)
    #expect(loaded.ruler == .standard(for: .millimeter))
    #expect(!loaded.productMetadata.rootSceneNodeIDs.isEmpty)
}

@Test func productMetadataRejectsInvalidSceneReference() async throws {
    var document = DesignDocument.empty()
    var metadata = ProductMetadata.empty()
    let rootID = try #require(metadata.rootSceneNodeIDs.first)
    metadata.sceneNodes[rootID]?.reference = .feature(FeatureID())
    document.productMetadata = metadata

    var caught: DocumentValidationError?
    do {
        try document.validate()
    } catch let error as DocumentValidationError {
        caught = error
    }

    guard case .invalidProductMetadata(let message) = caught else {
        #expect(Bool(false))
        return
    }
    #expect(message.contains("existing CAD feature"))
}

@MainActor
@Test func documentExportServiceWritesEvaluatedModelArtifact() async throws {
    let temporaryDirectory = try makeTemporaryDirectory()
    defer {
        removeTemporaryDirectory(temporaryDirectory)
    }

    let session = EditorSession()
    _ = try session.execute(
        .createExtrudedRectangle(
            name: "Export Box",
            plane: .xy,
            width: .length(40.0, .millimeter),
            height: .length(20.0, .millimeter),
            depth: .length(10.0, .millimeter),
            direction: .normal
        )
    )

    let outputURL = temporaryDirectory.appendingPathComponent("box.stl")
    let result = try DocumentExportService().export(
        document: session.document,
        generation: session.generation,
        to: outputURL
    )

    #expect(result.format == .stl)
    #expect(result.generation == DocumentGeneration(1))
    #expect(result.outputPath == outputURL.path)
    #expect(result.byteCount == 84 + 12 * 50)
    #expect(FileManager.default.fileExists(atPath: outputURL.path))
}

@MainActor
@Test func documentExportServiceUsesPresetUnitAndReportsPolicy() async throws {
    let temporaryDirectory = try makeTemporaryDirectory()
    defer {
        removeTemporaryDirectory(temporaryDirectory)
    }

    let preset = ExportPreset(
        name: "Micro STL",
        format: .stl,
        outputUnit: .micrometer,
        destinationPolicy: .overwrite
    )
    var metadata = ProductMetadata.empty()
    metadata.exportPresets = [preset.id: preset]
    var document = DesignDocument.empty(named: "Preset Export")
    document.productMetadata = metadata
    let session = EditorSession(document: document)
    _ = try session.execute(
        .createExtrudedRectangle(
            name: "Micro Box",
            plane: .xy,
            width: .length(40.0, .millimeter),
            height: .length(20.0, .millimeter),
            depth: .length(10.0, .millimeter),
            direction: .normal
        )
    )

    let outputURL = temporaryDirectory.appendingPathComponent("micro-box.stl")
    let result = try DocumentExportService().export(
        document: session.document,
        generation: session.generation,
        to: outputURL,
        options: ExportOptions(presetName: "Micro STL")
    )

    let header = String(decoding: try Data(contentsOf: outputURL).prefix(80), as: UTF8.self)
    #expect(result.presetName == "Micro STL")
    #expect(result.outputUnit == .micrometer)
    #expect(result.destinationPolicy == .overwrite)
    #expect(header.contains("unit=micrometer"))
}

@MainActor
@Test func documentExportServicePromptPolicyRejectsExistingOutput() async throws {
    let temporaryDirectory = try makeTemporaryDirectory()
    defer {
        removeTemporaryDirectory(temporaryDirectory)
    }

    let session = EditorSession()
    _ = try session.execute(
        .createExtrudedRectangle(
            name: "Prompt Box",
            plane: .xy,
            width: .length(10.0, .millimeter),
            height: .length(10.0, .millimeter),
            depth: .length(10.0, .millimeter),
            direction: .normal
        )
    )

    let outputURL = temporaryDirectory.appendingPathComponent("prompt-box.stl")
    try Data("existing".utf8).write(to: outputURL)
    var caught: EditorError?
    do {
        _ = try DocumentExportService().export(
            document: session.document,
            generation: session.generation,
            to: outputURL,
            options: ExportOptions(destinationPolicy: .prompt)
        )
    } catch let error as EditorError {
        caught = error
    }

    #expect(caught?.code == .exportFailed)
    #expect(String(decoding: try Data(contentsOf: outputURL), as: UTF8.self) == "existing")
}

@MainActor
@Test func documentExportServiceVersionedPolicyWritesNextAvailableOutput() async throws {
    let temporaryDirectory = try makeTemporaryDirectory()
    defer {
        removeTemporaryDirectory(temporaryDirectory)
    }

    let session = EditorSession()
    _ = try session.execute(
        .createExtrudedRectangle(
            name: "Versioned Box",
            plane: .xy,
            width: .length(10.0, .millimeter),
            height: .length(10.0, .millimeter),
            depth: .length(10.0, .millimeter),
            direction: .normal
        )
    )

    let outputURL = temporaryDirectory.appendingPathComponent("versioned-box.stl")
    let versionedURL = temporaryDirectory.appendingPathComponent("versioned-box-1.stl")
    try Data("existing".utf8).write(to: outputURL)
    let result = try DocumentExportService().export(
        document: session.document,
        generation: session.generation,
        to: outputURL,
        options: ExportOptions(destinationPolicy: .versioned)
    )

    #expect(result.outputPath == versionedURL.path)
    #expect(result.destinationPolicy == .versioned)
    #expect(String(decoding: try Data(contentsOf: outputURL), as: UTF8.self) == "existing")
    #expect(FileManager.default.fileExists(atPath: versionedURL.path))
}

@MainActor
@Test func documentExportServiceRejectsPresetFormatMismatch() async throws {
    let temporaryDirectory = try makeTemporaryDirectory()
    defer {
        removeTemporaryDirectory(temporaryDirectory)
    }

    let preset = ExportPreset(
        name: "Print STL",
        format: .stl,
        outputUnit: .millimeter,
        destinationPolicy: .overwrite
    )
    var metadata = ProductMetadata.empty()
    metadata.exportPresets = [preset.id: preset]
    var document = DesignDocument.empty(named: "Mismatched Export")
    document.productMetadata = metadata
    let session = EditorSession(document: document)
    _ = try session.execute(
        .createExtrudedRectangle(
            name: "Mismatch Box",
            plane: .xy,
            width: .length(10.0, .millimeter),
            height: .length(10.0, .millimeter),
            depth: .length(10.0, .millimeter),
            direction: .normal
        )
    )

    let outputURL = temporaryDirectory.appendingPathComponent("mismatch.obj")
    var caught: EditorError?
    do {
        _ = try DocumentExportService().export(
            document: session.document,
            generation: session.generation,
            to: outputURL,
            options: ExportOptions(presetName: "Print STL")
        )
    } catch let error as EditorError {
        caught = error
    }

    #expect(caught?.code == .commandInvalid)
    #expect(!FileManager.default.fileExists(atPath: outputURL.path))
}

@Test func documentExportServiceRejectsNonEvaluatingDocumentWithoutCreatingOutput() async throws {
    let temporaryDirectory = try makeTemporaryDirectory()
    defer {
        removeTemporaryDirectory(temporaryDirectory)
    }

    let outputURL = temporaryDirectory.appendingPathComponent("empty.stl")
    var caught: EditorError?
    do {
        _ = try DocumentExportService().export(
            document: .empty(named: "Empty"),
            generation: DocumentGeneration(0),
            to: outputURL
        )
    } catch let error as EditorError {
        caught = error
    }

    #expect(caught?.code == .evaluationFailed)
    #expect(!FileManager.default.fileExists(atPath: outputURL.path))
}

@MainActor
@Test func documentExportServiceDryRunEvaluatesWithoutWritingOutput() async throws {
    let temporaryDirectory = try makeTemporaryDirectory()
    defer {
        removeTemporaryDirectory(temporaryDirectory)
    }

    let session = EditorSession()
    _ = try session.execute(
        .createExtrudedRectangle(
            name: "Dry Export Box",
            plane: .xy,
            width: .length(10.0, .millimeter),
            height: .length(10.0, .millimeter),
            depth: .length(10.0, .millimeter),
            direction: .normal
        )
    )

    let outputURL = temporaryDirectory.appendingPathComponent("dry-box.stl")
    let result = try DocumentExportService().export(
        document: session.document,
        generation: session.generation,
        to: outputURL,
        dryRun: true
    )

    #expect(result.dryRun)
    #expect(result.byteCount == 0)
    #expect(result.format == .stl)
    #expect(!FileManager.default.fileExists(atPath: outputURL.path))
}

private func sketchBounds(
    _ sketch: Sketch,
    parameters: ParameterTable
) throws -> (width: Double, height: Double) {
    var points: [(x: Double, y: Double)] = []
    for entity in sketch.entities.values {
        switch entity {
        case .point(let point):
            points.append(try resolvedPoint(point, parameters: parameters))
        case .line(let line):
            points.append(try resolvedPoint(line.start, parameters: parameters))
            points.append(try resolvedPoint(line.end, parameters: parameters))
        case .circle(let circle):
            let center = try resolvedPoint(circle.center, parameters: parameters)
            let radius = try resolvedLength(circle.radius, parameters: parameters)
            points.append((x: center.x - radius, y: center.y - radius))
            points.append((x: center.x + radius, y: center.y + radius))
        case .arc(let arc):
            let center = try resolvedPoint(arc.center, parameters: parameters)
            let radius = try resolvedLength(arc.radius, parameters: parameters)
            points.append((x: center.x - radius, y: center.y - radius))
            points.append((x: center.x + radius, y: center.y + radius))
        case .spline(let spline):
            for point in spline.controlPoints {
                points.append(try resolvedPoint(point, parameters: parameters))
            }
        }
    }
    let first = try #require(points.first)
    let minX = points.dropFirst().reduce(first.x) { min($0, $1.x) }
    let maxX = points.dropFirst().reduce(first.x) { max($0, $1.x) }
    let minY = points.dropFirst().reduce(first.y) { min($0, $1.y) }
    let maxY = points.dropFirst().reduce(first.y) { max($0, $1.y) }
    return (width: maxX - minX, height: maxY - minY)
}

private func generatedDepthEdge(
    in topology: TopologySummaryResult
) -> TopologySummaryResult.Entry? {
    topology.entries.first { entry in
        guard entry.kind == .edge,
              entry.generatedRole == "edge",
              entry.curveKind == "line",
              let start = entry.start,
              let end = entry.end else {
            return false
        }
        let tolerance = 1.0e-9
        return abs(start.x - end.x) <= tolerance &&
            abs(start.y - end.y) <= tolerance &&
            abs(start.z - end.z) > tolerance
    }
}

private func opposingGeneratedFaceTargets(
    in document: DesignDocument
) throws -> (first: SelectionTarget, second: SelectionTarget) {
    let topology = try TopologySummaryService().summarize(document: document)
    let faces = try topology.entries.compactMap { entry -> (centerZ: Double, target: SelectionTarget)? in
        guard entry.kind == .face,
              let centerZ = entry.center?.z else {
            return nil
        }
        return (centerZ, try #require(entry.selectionTarget()))
    }
    let first = try #require(faces.min { $0.centerZ < $1.centerZ })
    let second = try #require(faces.max { $0.centerZ < $1.centerZ })
    #expect(second.centerZ - first.centerZ > 0.0)
    return (first.target, second.target)
}

private func resolvedPoint(
    _ point: SketchPoint,
    parameters: ParameterTable
) throws -> (x: Double, y: Double) {
    (
        x: try resolvedLength(point.x, parameters: parameters),
        y: try resolvedLength(point.y, parameters: parameters)
    )
}

private func resolvedLength(
    _ expression: CADExpression,
    parameters: ParameterTable
) throws -> Double {
    let quantity = try parameters.resolvedValue(for: expression)
    return quantity.value
}

private func resolvedSketchPoint(
    _ point: SketchPoint,
    in document: DesignDocument
) throws -> (x: Double, y: Double) {
    (
        x: try resolvedLength(point.x, parameters: document.cadDocument.parameters),
        y: try resolvedLength(point.y, parameters: document.cadDocument.parameters)
    )
}

private func distance(
    from first: (x: Double, y: Double),
    to second: (x: Double, y: Double)
) -> Double {
    let deltaX = first.x - second.x
    let deltaY = first.y - second.y
    return sqrt(deltaX * deltaX + deltaY * deltaY)
}

private func distanceFromOrigin(
    toLineFrom start: (x: Double, y: Double),
    to end: (x: Double, y: Double)
) -> Double {
    let numerator = abs((end.x - start.x) * start.y - (end.y - start.y) * start.x)
    let denominator = distance(from: start, to: end)
    return numerator / denominator
}

private func designDocumentPolySplineQuadMesh() -> Mesh {
    Mesh(
        positions: [
            Point3D(x: 0.0, y: 0.0, z: 0.0),
            Point3D(x: 0.02, y: 0.0, z: 0.0),
            Point3D(x: 0.02, y: 0.02, z: 0.004),
            Point3D(x: 0.0, y: 0.02, z: 0.0),
        ],
        indices: [0, 1, 2, 0, 2, 3]
    )
}

private func polySplineVertexTarget(
    role: String,
    in document: DesignDocument
) throws -> SelectionTarget {
    let topology = try TopologySummaryService().summarize(document: document)
    let entry = try #require(topology.entries.first {
        $0.kind == .vertex
            && $0.subshapeRole == role
    })
    return try #require(entry.selectionTarget())
}

private func designDocumentPolySplinePatchNetworkMesh(centerZ: Double = 0.001) -> Mesh {
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

private func makeTemporaryDirectory() throws -> URL {
    let temporaryDirectory = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(
        at: temporaryDirectory,
        withIntermediateDirectories: true
    )
    return temporaryDirectory
}

private func removeTemporaryDirectory(_ url: URL) {
    do {
        try FileManager.default.removeItem(at: url)
    } catch {
        Issue.record("Failed to remove temporary directory: \(error)")
    }
}
