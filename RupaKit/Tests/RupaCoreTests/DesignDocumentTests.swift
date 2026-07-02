import Foundation
import SwiftCAD
import Testing
@testable import RupaCore

@Test func defaultDocumentUsesMetersInternally() async throws {
    let document = DesignDocument.empty()
    #expect(document.cadDocument.units.length.rawValue == "meter")
    #expect(document.cadDocument.units.angle.rawValue == "radian")
}

@Test func lengthDisplayUnitsCoverMicrometerThroughKilometer() async throws {
    #expect(LengthDisplayUnit.micrometer.metersPerUnit == 0.000_001)
    #expect(LengthDisplayUnit.meter.metersPerUnit == 1.0)
    #expect(LengthDisplayUnit.kilometer.metersPerUnit == 1_000.0)
}

@Test func lengthDisplayUnitsChooseReadableMetricScale() async throws {
    #expect(LengthDisplayUnit.millimeter.readableUnit(forMeters: 0.25) == .millimeter)
    #expect(LengthDisplayUnit.millimeter.readableUnit(forMeters: 1.0) == .meter)
    #expect(LengthDisplayUnit.meter.readableUnit(forMeters: 0.02) == .centimeter)
    #expect(LengthDisplayUnit.kilometer.readableUnit(forMeters: 0.25) == .centimeter)
    #expect(LengthDisplayUnit.meter.readableUnit(forMeters: 1_000.0) == .kilometer)
    #expect(LengthDisplayUnit.kilometer.readableUnit(forMeters: 1.0) == .meter)
    #expect(LengthDisplayUnit.meter.readableUnit(forMeters: 0.000_25) == .micrometer)
    #expect(LengthDisplayUnit.inch.readableUnit(forMeters: 0.3048) == .foot)
}

@Test func displayUnitChangePreservesWorkspaceScaleDistances() async throws {
    var document = DesignDocument.empty()
    let originalRuler = document.ruler

    document.setDisplayUnit(.kilometer)

    #expect(document.displayUnit == .kilometer)
    #expect(document.ruler.displayUnit == .kilometer)
    #expect(document.ruler.minorTickMeters == originalRuler.minorTickMeters)
    #expect(document.ruler.majorTickMeters == originalRuler.majorTickMeters)
    #expect(document.ruler.visibleSpanMeters == originalRuler.visibleSpanMeters)
}

@Test func rulerDisplayUnitReplacementPreservesSitePlanningRange() async throws {
    let ruler = WorkspaceScalePreset.sitePlanning.rulerConfiguration
    let replaced = ruler.replacingDisplayUnit(.millimeter)

    #expect(replaced.displayUnit == .millimeter)
    #expect(replaced.minorTickMeters == ruler.minorTickMeters)
    #expect(replaced.majorTickMeters == ruler.majorTickMeters)
    #expect(replaced.visibleSpanMeters == ruler.visibleSpanMeters)
    #expect(replaced.visibleSpanMeters == 100_000.0)
    try replaced.validate()
}

@Test func rulerScaleRangeCoversPrecisionMechanicsThroughArchitecture() async throws {
    #expect(RulerConfiguration.minorTickMetersRange.lowerBound == 1.0e-6)
    #expect(RulerConfiguration.visibleSpanMetersRange.upperBound >= 1_000_000.0)

    let configuration = RulerConfiguration(
        displayUnit: .millimeter,
        minorTickMeters: 1.0e-12,
        majorTickMeters: 1.0e-12,
        visibleSpanMeters: 1.0e9
    ).normalizedForWorkspaceScale()

    #expect(configuration.minorTickMeters == RulerConfiguration.minorTickMetersRange.lowerBound)
    #expect(configuration.majorTickMeters >= configuration.minorTickMeters * 2.0)
    #expect(configuration.visibleSpanMeters == RulerConfiguration.visibleSpanMetersRange.upperBound)
    try configuration.validate()
}

@Test func rulerValidationRejectsValuesOutsideWorkspaceScaleRange() async throws {
    let configuration = RulerConfiguration(
        displayUnit: .meter,
        minorTickMeters: 1.0,
        majorTickMeters: 10.0,
        visibleSpanMeters: RulerConfiguration.visibleSpanMetersRange.upperBound * 2.0
    )

    #expect(throws: DocumentValidationError.self) {
        try configuration.validate()
    }
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

@Test func builtInObjectCatalogBuildsValidatedRegistry() async throws {
    let validatedRegistry = try ObjectTypeRegistry(
        definitions: ObjectTypeCatalog.builtInDefinitions
    )

    #expect(validatedRegistry.definitions.count == ObjectTypeCatalog.builtInDefinitions.count)
    #expect(ObjectTypeRegistry.builtIn.definitions == validatedRegistry.definitions)
}

@Test func builtInObjectCatalogLengthRangesCoverSitePlanningScale() async throws {
    let siteDefaults = WorkspaceScaleDefaults(
        ruler: WorkspaceScalePreset.sitePlanning.rulerConfiguration
    )

    for definition in ObjectTypeCatalog.builtInDefinitions {
        for property in definition.properties where property.valueKind == .length {
            let range = try #require(
                property.numericRange,
                "Length property \(definition.id.rawValue).\(property.id.rawValue) must declare a numeric range."
            )
            #expect(range.lowerBound == 0.0)
            #expect(
                range.upperBound >= siteDefaults.baseFeatureMeters,
                "Length property \(definition.id.rawValue).\(property.id.rawValue) must support site-planning defaults."
            )
        }
    }
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
    document.setDisplayUnit(.millimeter)

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
    #expect(measuredPoint.displayUnit == .millimeter)
    #expect(measuredPoint.displayUnitSymbol == "mm")
    #expect(abs(measuredPoint.displayPoint.z - (override.point.z * 1_000.0)) <= 1.0e-12)
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

@Test func directBSplineSurfaceControlPointReferenceMutatesStoredControlNet() async throws {
    var document = DesignDocument.empty()

    let surface = designDocumentDirectBSplineSurface()
    let featureID = try document.createBSplineSurface(
        name: "Direct Editable Surface",
        surface: surface
    )
    let summary = try SurfaceSourceSummaryService().summarize(document: document)
    let controlPoint = try #require(
        summary.sources.first?.patches.first?.controlPoints.first { $0.uIndex == 1 && $0.vIndex == 1 }
    )
    #expect(controlPoint.isEditable)

    try document.moveSurfaceControlPoint(
        target: controlPoint.selectionReference,
        deltaX: .length(0.0, .millimeter),
        deltaY: .length(0.0, .millimeter),
        deltaZ: .length(1.0, .millimeter)
    )

    let movedFeature = try #require(document.cadDocument.designGraph.nodes[featureID])
    guard case let .bSplineSurface(movedSurfaceFeature) = movedFeature.operation else {
        Issue.record("Expected a direct B-spline surface feature.")
        return
    }
    let movedPoint = movedSurfaceFeature.surface.controlPoints[1][1]
    #expect(abs(movedPoint.x - controlPoint.point.x) <= 1.0e-12)
    #expect(abs(movedPoint.y - controlPoint.point.y) <= 1.0e-12)
    #expect(abs(movedPoint.z - (controlPoint.point.z + 0.001)) <= 1.0e-12)
    #expect(movedSurfaceFeature.surface.weights[1][1] == 2.0)

    try document.setSurfaceControlPointWeight(
        target: controlPoint.selectionReference,
        weight: .scalar(2.5)
    )

    let weightedFeature = try #require(document.cadDocument.designGraph.nodes[featureID])
    guard case let .bSplineSurface(weightedSurfaceFeature) = weightedFeature.operation else {
        Issue.record("Expected a weighted direct B-spline surface feature.")
        return
    }
    #expect(weightedSurfaceFeature.surface.weights[1][1] == 2.5)
    #expect(weightedSurfaceFeature.surface.isRational)

    try document.slideSurfaceControlPoints(
        targets: [controlPoint.selectionReference],
        direction: .positiveU,
        distance: .length(1.0, .millimeter)
    )

    let slidFeature = try #require(document.cadDocument.designGraph.nodes[featureID])
    guard case let .bSplineSurface(slidSurfaceFeature) = slidFeature.operation else {
        Issue.record("Expected a slid direct B-spline surface feature.")
        return
    }
    let slidPoint = slidSurfaceFeature.surface.controlPoints[1][1]
    #expect(abs(slidPoint.x - (controlPoint.point.x + 0.001)) <= 1.0e-12)
    #expect(abs(slidPoint.y - controlPoint.point.y) <= 1.0e-12)
    #expect(abs(slidPoint.z - (controlPoint.point.z + 0.001)) <= 1.0e-12)
    #expect(slidSurfaceFeature.surface.weights[1][1] == 2.5)

    let updatedSummary = try SurfaceSourceSummaryService().summarize(document: document)
    let updatedPatch = try #require(updatedSummary.sources.first?.patches.first)
    let updatedControlPoint = try #require(
        updatedPatch.controlPoints.first { $0.uIndex == 1 && $0.vIndex == 1 }
    )
    #expect(updatedPatch.basis.isRational)
    #expect(updatedControlPoint.weight == 2.5)
    #expect(abs(updatedControlPoint.point.x - slidPoint.x) <= 1.0e-12)
    #expect(abs(updatedControlPoint.point.z - slidPoint.z) <= 1.0e-12)
}

@Test func directBSplineSurfaceControlPointFrameMoveUsesResolvedUVNFrame() async throws {
    var document = DesignDocument.empty()

    let featureID = try document.createBSplineSurface(
        name: "Frame Editable Surface",
        surface: designDocumentDirectBSplineSurface()
    )
    let summary = try SurfaceSourceSummaryService().summarize(document: document)
    let patch = try #require(summary.sources.first?.patches.first)
    let controlPoint = try #require(
        patch.controlPoints.first { $0.uIndex == 1 && $0.vIndex == 1 }
    )
    let frameSample = try #require(patch.frameSamples.first)
    let frameQuery = SurfaceFrameQuery(selectionReference: frameSample.selectionReference)
    let frameResult = try SurfaceFrameService().resolve(document: document, queries: [frameQuery])
    let frame = try #require(frameResult.frames.first)
    let uDistance = 0.001
    let vDistance = 0.002
    let normalDistance = 0.003

    try document.moveSurfaceControlPointsInFrame(
        targets: [controlPoint.selectionReference],
        frame: frameQuery,
        uDistance: .length(uDistance, .meter),
        vDistance: .length(vDistance, .meter),
        normalDistance: .length(normalDistance, .meter)
    )

    let movedFeature = try #require(document.cadDocument.designGraph.nodes[featureID])
    guard case let .bSplineSurface(movedSurfaceFeature) = movedFeature.operation else {
        Issue.record("Expected a direct B-spline surface feature.")
        return
    }
    let movedPoint = movedSurfaceFeature.surface.controlPoints[1][1]
    let expectedX = controlPoint.point.x
        + frame.uAxis.x * uDistance
        + frame.vAxis.x * vDistance
        + frame.normal.x * normalDistance
    let expectedY = controlPoint.point.y
        + frame.uAxis.y * uDistance
        + frame.vAxis.y * vDistance
        + frame.normal.y * normalDistance
    let expectedZ = controlPoint.point.z
        + frame.uAxis.z * uDistance
        + frame.vAxis.z * vDistance
        + frame.normal.z * normalDistance
    #expect(abs(movedPoint.x - expectedX) <= 1.0e-12)
    #expect(abs(movedPoint.y - expectedY) <= 1.0e-12)
    #expect(abs(movedPoint.z - expectedZ) <= 1.0e-12)
}

@Test func directBSplineSurfaceKnotReferenceMutatesStoredKnotVector() async throws {
    var document = DesignDocument.empty()

    let featureID = try document.createBSplineSurface(
        name: "Direct Editable Knot Surface",
        surface: designDocumentDirectBSplineSurfaceWithInteriorKnots()
    )
    let summary = try SurfaceSourceSummaryService().summarize(document: document)
    let patch = try #require(summary.sources.first?.patches.first)
    let editableKnot = try #require(patch.basis.uKnotVector.first { $0.index == 3 })
    #expect(editableKnot.value == 0.5)
    #expect(editableKnot.isEditable)
    let knotReference = try #require(editableKnot.selectionReference)

    try document.setSurfaceKnotValue(
        target: knotReference,
        value: .scalar(0.4)
    )

    let feature = try #require(document.cadDocument.designGraph.nodes[featureID])
    guard case let .bSplineSurface(surfaceFeature) = feature.operation else {
        Issue.record("Expected a direct B-spline surface feature.")
        return
    }
    #expect(surfaceFeature.surface.uKnots[3] == 0.4)
    #expect(surfaceFeature.surface.vKnots[3] == 0.5)

    let updatedSummary = try SurfaceSourceSummaryService().summarize(document: document)
    let updatedKnot = try #require(
        updatedSummary.sources.first?.patches.first?.basis.uKnotVector.first { $0.index == 3 }
    )
    #expect(updatedKnot.value == 0.4)
    #expect(updatedKnot.isEditable)

    let boundaryKnot = try #require(patch.basis.uKnotVector.first { $0.index == 0 })
    let boundaryReference = try #require(boundaryKnot.selectionReference)
    #expect(boundaryKnot.isEditable == false)
    #expect(throws: EditorError.self) {
        try document.setSurfaceKnotValue(
            target: boundaryReference,
            value: .scalar(0.1)
        )
    }
}

@Test func directBSplineSurfaceSpanReferenceInsertsShapePreservingKnot() async throws {
    var document = DesignDocument.empty()
    let surface = designDocumentDirectBSplineSurfaceWithInteriorKnots()

    let featureID = try document.createBSplineSurface(
        name: "Direct Insertable Knot Surface",
        surface: surface
    )
    let summary = try SurfaceSourceSummaryService().summarize(document: document)
    let patch = try #require(summary.sources.first?.patches.first)
    let editableSpan = try #require(patch.basis.uSpans.first { $0.index == 0 })
    #expect(editableSpan.isEditable)
    let spanReference = try #require(editableSpan.selectionReference)

    try document.insertSurfaceKnot(
        target: spanReference,
        value: .scalar(0.25)
    )

    let feature = try #require(document.cadDocument.designGraph.nodes[featureID])
    guard case let .bSplineSurface(surfaceFeature) = feature.operation else {
        Issue.record("Expected a direct B-spline surface feature.")
        return
    }
    #expect(surfaceFeature.surface.uKnots == [0.0, 0.0, 0.0, 0.25, 0.5, 1.0, 1.0, 1.0])
    #expect(surfaceFeature.surface.vKnots == surface.vKnots)
    #expect(surfaceFeature.surface.uControlPointCount == surface.uControlPointCount + 1)
    #expect(surfaceFeature.surface.vControlPointCount == surface.vControlPointCount)
    for u in [0.0, 0.2, 0.45, 0.8, 1.0] {
        for v in [0.0, 0.3, 0.6, 1.0] {
            let before = try surface.point(u: u, v: v)
            let after = try surfaceFeature.surface.point(u: u, v: v)
            #expect(abs(before.x - after.x) <= 1.0e-10)
            #expect(abs(before.y - after.y) <= 1.0e-10)
            #expect(abs(before.z - after.z) <= 1.0e-10)
        }
    }
    #expect(throws: EditorError.self) {
        try document.insertSurfaceKnot(
            target: spanReference,
            value: .scalar(0.75)
        )
    }
}

@Test func directBSplineSurfaceSpanReferenceSplitsSpanByFraction() async throws {
    var document = DesignDocument.empty()
    let surface = designDocumentDirectBSplineSurfaceWithInteriorKnots()

    let featureID = try document.createBSplineSurface(
        name: "Direct Split Span Surface",
        surface: surface
    )
    let summary = try SurfaceSourceSummaryService().summarize(document: document)
    let patch = try #require(summary.sources.first?.patches.first)
    let editableSpan = try #require(patch.basis.vSpans.first { $0.index == 1 })
    #expect(editableSpan.lowerBound == 0.5)
    #expect(editableSpan.upperBound == 1.0)
    let spanReference = try #require(editableSpan.selectionReference)

    try document.splitSurfaceSpan(
        target: spanReference,
        fraction: .scalar(0.25)
    )

    let feature = try #require(document.cadDocument.designGraph.nodes[featureID])
    guard case let .bSplineSurface(surfaceFeature) = feature.operation else {
        Issue.record("Expected a direct B-spline surface feature.")
        return
    }
    #expect(surfaceFeature.surface.uKnots == surface.uKnots)
    #expect(surfaceFeature.surface.vKnots == [0.0, 0.0, 0.0, 0.5, 0.625, 1.0, 1.0, 1.0])
    #expect(surfaceFeature.surface.uControlPointCount == surface.uControlPointCount)
    #expect(surfaceFeature.surface.vControlPointCount == surface.vControlPointCount + 1)
    for u in [0.0, 0.2, 0.45, 0.8, 1.0] {
        for v in [0.0, 0.3, 0.625, 0.9, 1.0] {
            let before = try surface.point(u: u, v: v)
            let after = try surfaceFeature.surface.point(u: u, v: v)
            #expect(abs(before.x - after.x) <= 1.0e-10)
            #expect(abs(before.y - after.y) <= 1.0e-10)
            #expect(abs(before.z - after.z) <= 1.0e-10)
        }
    }
    #expect(throws: EditorError.self) {
        try document.splitSurfaceSpan(
            target: spanReference,
            fraction: .scalar(0.0)
        )
    }
    let knotReference = try #require(patch.basis.uKnotVector.first?.selectionReference)
    #expect(throws: EditorError.self) {
        try document.splitSurfaceSpan(
            target: knotReference,
            fraction: .scalar(0.5)
        )
    }
}

@Test func directBSplineSurfaceTrimDomainUpdatesSummaryAndContinuityContracts() async throws {
    var document = DesignDocument.empty()
    let surface = designDocumentDirectBSplineSurfaceWithInteriorKnots()

    let featureID = try document.createBSplineSurface(
        name: "Direct Trim Domain Surface",
        surface: surface
    )
    let summary = try SurfaceSourceSummaryService().summarize(document: document)
    let patch = try #require(summary.sources.first?.patches.first)
    let faceReference = try #require(patch.faceSelectionReference)

    try document.setSurfaceTrimDomain(
        target: faceReference,
        uLowerBound: .scalar(0.25),
        uUpperBound: .scalar(0.75),
        vLowerBound: .scalar(0.2),
        vUpperBound: .scalar(0.8)
    )

    let feature = try #require(document.cadDocument.designGraph.nodes[featureID])
    guard case let .bSplineSurface(surfaceFeature) = feature.operation else {
        Issue.record("Expected a direct B-spline surface feature.")
        return
    }
    let trimDomain = try #require(surfaceFeature.outerTrimDomain)
    #expect(trimDomain.uLowerBound == 0.25)
    #expect(trimDomain.uUpperBound == 0.75)
    #expect(trimDomain.vLowerBound == 0.2)
    #expect(trimDomain.vUpperBound == 0.8)

    let trimmedSummary = try SurfaceSourceSummaryService().summarize(document: document)
    let trimmedPatch = try #require(trimmedSummary.sources.first?.patches.first)
    #expect(trimmedPatch.uDomain.lowerBound == 0.25)
    #expect(trimmedPatch.uDomain.upperBound == 0.75)
    #expect(trimmedPatch.vDomain.lowerBound == 0.2)
    #expect(trimmedPatch.vDomain.upperBound == 0.8)
    #expect(trimmedPatch.frameSamples.allSatisfy { sample in
        sample.u >= 0.25 && sample.u <= 0.75 && sample.v >= 0.2 && sample.v <= 0.8
    })
    let trimmedEdges = try #require(trimmedPatch.trimLoops.first?.edges)
    #expect(trimmedEdges.allSatisfy { !$0.supportsBoundaryContinuityMatching })
    #expect(trimmedEdges.allSatisfy { $0.boundaryControlPointReferences.isEmpty })
    #expect(trimmedEdges.allSatisfy { edge in
        edge.unsupportedReason == "Interior rectangular trim domains do not expose boundary control rows for continuity matching."
    })
    let trimReference = try #require(trimmedPatch.trimLoops.first?.selectionReferences.first)
    #expect(throws: EditorError.self) {
        try document.surfaceBoundaryContinuityCompatibility(
            target: trimReference,
            reference: trimReference
        )
    }

    #expect(throws: EditorError.self) {
        try document.setSurfaceTrimDomain(
            target: faceReference,
            uLowerBound: .scalar(0.75),
            uUpperBound: .scalar(0.25),
            vLowerBound: .scalar(0.2),
            vUpperBound: .scalar(0.8)
        )
    }

    try document.setSurfaceTrimDomain(
        target: faceReference,
        uLowerBound: .scalar(0.0),
        uUpperBound: .scalar(1.0),
        vLowerBound: .scalar(0.0),
        vUpperBound: .scalar(1.0)
    )
    let resetFeature = try #require(document.cadDocument.designGraph.nodes[featureID])
    guard case let .bSplineSurface(resetSurfaceFeature) = resetFeature.operation else {
        Issue.record("Expected a direct B-spline surface feature after reset.")
        return
    }
    #expect(resetSurfaceFeature.outerTrimDomain == nil)
}

@Test func directBSplineSurfaceTrimLoopsUpdateSummaryAndContinuityContracts() async throws {
    var document = DesignDocument.empty()
    let surface = designDocumentDirectBSplineSurfaceWithInteriorKnots()

    let featureID = try document.createBSplineSurface(
        name: "Direct Trim Loop Surface",
        surface: surface
    )
    let summary = try SurfaceSourceSummaryService().summarize(document: document)
    let faceReference = try #require(summary.sources.first?.patches.first?.faceSelectionReference)
    let rectangularTrimReference = try #require(summary.sources.first?.patches.first?.trimLoops.first?.selectionReferences.first)
    #expect(throws: EditorError.self) {
        try document.moveSurfaceTrimEndpoint(
            target: rectangularTrimReference,
            endpoint: .start,
            u: .scalar(0.25),
            v: .scalar(0.3)
        )
    }

    let trimLoop = BSplineSurfaceTrimLoop(
        role: .outer,
        edges: [
            BSplineSurfaceTrimEdge(parameterCurve: .polyline([
                SurfaceParameter(u: 0.2, v: 0.2),
                SurfaceParameter(u: 0.8, v: 0.25),
            ])),
            BSplineSurfaceTrimEdge(parameterCurve: .polyline([
                SurfaceParameter(u: 0.8, v: 0.25),
                SurfaceParameter(u: 0.45, v: 0.8),
            ])),
            BSplineSurfaceTrimEdge(parameterCurve: .polyline([
                SurfaceParameter(u: 0.45, v: 0.8),
                SurfaceParameter(u: 0.2, v: 0.2),
            ])),
        ]
    )

    try document.setSurfaceTrimLoops(
        target: faceReference,
        trimLoops: [trimLoop]
    )

    let feature = try #require(document.cadDocument.designGraph.nodes[featureID])
    guard case let .bSplineSurface(surfaceFeature) = feature.operation else {
        Issue.record("Expected a direct B-spline surface feature.")
        return
    }
    #expect(surfaceFeature.outerTrimDomain == nil)
    #expect(surfaceFeature.trimLoops == [trimLoop])

    let trimmedSummary = try SurfaceSourceSummaryService().summarize(document: document)
    let trimmedPatch = try #require(trimmedSummary.sources.first?.patches.first)
    #expect(trimmedPatch.uDomain.lowerBound == 0.0)
    #expect(trimmedPatch.uDomain.upperBound == 1.0)
    #expect(trimmedPatch.vDomain.lowerBound == 0.0)
    #expect(trimmedPatch.vDomain.upperBound == 1.0)
    let summaryTrimLoop = try #require(trimmedPatch.trimLoops.first)
    #expect(summaryTrimLoop.edges.count == 3)
    #expect(summaryTrimLoop.edgePersistentNames.count == 3)
    #expect(summaryTrimLoop.selectionReferences.count == 3)
    #expect(summaryTrimLoop.parameterAddresses.map(\.id) == [
        "loop:0:edge:0:start",
        "loop:0:edge:1:start",
        "loop:0:edge:2:start",
    ])
    #expect(summaryTrimLoop.edgePersistentNames.allSatisfy { $0.contains("subshape:patch:0:loop:0:edge:") })
    #expect(summaryTrimLoop.edges.allSatisfy { !$0.supportsBoundaryContinuityMatching })
    #expect(summaryTrimLoop.edges.allSatisfy { edge in
        edge.unsupportedReason == "Authored trim edges do not expose boundary control rows for continuity matching."
    })
    #expect(trimmedSummary.sources.first?.diagnostics.contains { diagnostic in
        diagnostic.code == "directBSplineSurfaceTrimLoops"
    } == true)

    let trimReference = try #require(summaryTrimLoop.selectionReferences.first)
    #expect(throws: EditorError.self) {
        try document.surfaceBoundaryContinuityCompatibility(
            target: trimReference,
            reference: trimReference
        )
    }

    try document.setSurfaceTrimLoops(
        target: faceReference,
        trimLoops: []
    )
    let resetFeature = try #require(document.cadDocument.designGraph.nodes[featureID])
    guard case let .bSplineSurface(resetSurfaceFeature) = resetFeature.operation else {
        Issue.record("Expected a direct B-spline surface feature after reset.")
        return
    }
    #expect(resetSurfaceFeature.outerTrimDomain == nil)
    #expect(resetSurfaceFeature.trimLoops.isEmpty)
}

@Test func directBSplineSurfaceTrimEndpointMovePreservesAuthoredLoopClosure() async throws {
    var document = DesignDocument.empty()
    let surface = designDocumentDirectBSplineSurfaceWithInteriorKnots()

    let featureID = try document.createBSplineSurface(
        name: "Direct Trim Endpoint Surface",
        surface: surface
    )
    let summary = try SurfaceSourceSummaryService().summarize(document: document)
    let faceReference = try #require(summary.sources.first?.patches.first?.faceSelectionReference)
    let trimLoop = BSplineSurfaceTrimLoop(
        role: .outer,
        edges: [
            BSplineSurfaceTrimEdge(parameterCurve: .polyline([
                SurfaceParameter(u: 0.2, v: 0.2),
                SurfaceParameter(u: 0.8, v: 0.25),
            ])),
            BSplineSurfaceTrimEdge(parameterCurve: .polyline([
                SurfaceParameter(u: 0.8, v: 0.25),
                SurfaceParameter(u: 0.45, v: 0.8),
            ])),
            BSplineSurfaceTrimEdge(parameterCurve: .polyline([
                SurfaceParameter(u: 0.45, v: 0.8),
                SurfaceParameter(u: 0.2, v: 0.2),
            ])),
        ]
    )
    try document.setSurfaceTrimLoops(
        target: faceReference,
        trimLoops: [trimLoop]
    )
    let trimmedSummary = try SurfaceSourceSummaryService().summarize(document: document)
    let trimReference = try #require(
        trimmedSummary.sources.first?.patches.first?.trimLoops.first?.selectionReferences.first
    )

    try document.moveSurfaceTrimEndpoint(
        target: trimReference,
        endpoint: .start,
        u: .scalar(0.25),
        v: .scalar(0.3)
    )

    let feature = try #require(document.cadDocument.designGraph.nodes[featureID])
    guard case let .bSplineSurface(surfaceFeature) = feature.operation else {
        Issue.record("Expected a direct B-spline surface feature.")
        return
    }
    let movedLoop = try #require(surfaceFeature.trimLoops.first)
    let movedParameter = SurfaceParameter(u: 0.25, v: 0.3)
    #expect(try movedLoop.edges[0].startParameter().isApproximatelyEqual(to: movedParameter, tolerance: 1.0e-12))
    #expect(try movedLoop.edges[2].endParameter().isApproximatelyEqual(to: movedParameter, tolerance: 1.0e-12))
    #expect(try movedLoop.edges[0].endParameter().isApproximatelyEqual(
        to: SurfaceParameter(u: 0.8, v: 0.25),
        tolerance: 1.0e-12
    ))
    #expect(try movedLoop.edges[2].startParameter().isApproximatelyEqual(
        to: SurfaceParameter(u: 0.45, v: 0.8),
        tolerance: 1.0e-12
    ))
    try movedLoop.validate(on: surfaceFeature.surface)

    let movedSummary = try SurfaceSourceSummaryService().summarize(document: document)
    let movedEdge = try #require(movedSummary.sources.first?.patches.first?.trimLoops.first?.edges.first)
    #expect(abs(movedEdge.startParameter.u - 0.25) < 1.0e-12)
    #expect(abs(movedEdge.startParameter.v - 0.3) < 1.0e-12)
}

@Test func directBSplineSurfaceTrimControlPointMovePreservesAuthoredLoopEndpoints() async throws {
    var document = DesignDocument.empty()
    let surface = designDocumentDirectBSplineSurfaceWithInteriorKnots()

    let featureID = try document.createBSplineSurface(
        name: "Direct Trim Control Point Surface",
        surface: surface
    )
    let summary = try SurfaceSourceSummaryService().summarize(document: document)
    let faceReference = try #require(summary.sources.first?.patches.first?.faceSelectionReference)
    let trimLoop = BSplineSurfaceTrimLoop(
        role: .outer,
        edges: [
            BSplineSurfaceTrimEdge(parameterCurve: .bSpline(BSplineCurve2D(
                degree: 2,
                knots: [0.0, 0.0, 0.0, 1.0, 1.0, 1.0],
                controlPoints: [
                    Point2D(x: 0.2, y: 0.2),
                    Point2D(x: 0.52, y: 0.42),
                    Point2D(x: 0.8, y: 0.25),
                ]
            ))),
            BSplineSurfaceTrimEdge(parameterCurve: .polyline([
                SurfaceParameter(u: 0.8, v: 0.25),
                SurfaceParameter(u: 0.45, v: 0.8),
            ])),
            BSplineSurfaceTrimEdge(parameterCurve: .polyline([
                SurfaceParameter(u: 0.45, v: 0.8),
                SurfaceParameter(u: 0.2, v: 0.2),
            ])),
        ]
    )
    try document.setSurfaceTrimLoops(
        target: faceReference,
        trimLoops: [trimLoop]
    )
    let trimmedSummary = try SurfaceSourceSummaryService().summarize(document: document)
    let trimReference = try #require(
        trimmedSummary.sources.first?.patches.first?.trimLoops.first?.selectionReferences.first
    )

    #expect(throws: EditorError.self) {
        try document.moveSurfaceTrimControlPoint(
            target: trimReference,
            controlPointIndex: 0,
            u: .scalar(0.25),
            v: .scalar(0.3)
        )
    }

    try document.moveSurfaceTrimControlPoint(
        target: trimReference,
        controlPointIndex: 1,
        u: .scalar(0.58),
        v: .scalar(0.46)
    )

    let feature = try #require(document.cadDocument.designGraph.nodes[featureID])
    guard case let .bSplineSurface(surfaceFeature) = feature.operation else {
        Issue.record("Expected a direct B-spline surface feature.")
        return
    }
    let movedLoop = try #require(surfaceFeature.trimLoops.first)
    guard case .bSpline(let movedCurve) = movedLoop.edges[0].parameterCurve else {
        Issue.record("Expected a B-spline trim parameter curve.")
        return
    }
    #expect(movedCurve.controlPoints[0] == Point2D(x: 0.2, y: 0.2))
    #expect(movedCurve.controlPoints[1] == Point2D(x: 0.58, y: 0.46))
    #expect(movedCurve.controlPoints[2] == Point2D(x: 0.8, y: 0.25))
    #expect(try movedLoop.edges[0].startParameter().isApproximatelyEqual(
        to: SurfaceParameter(u: 0.2, v: 0.2),
        tolerance: 1.0e-12
    ))
    #expect(try movedLoop.edges[0].endParameter().isApproximatelyEqual(
        to: SurfaceParameter(u: 0.8, v: 0.25),
        tolerance: 1.0e-12
    ))
    try movedLoop.validate(on: surfaceFeature.surface)
}

@Test func directBSplineSurfaceTrimControlPointWeightUpdatesAuthoredBSplinePcurve() async throws {
    var document = DesignDocument.empty()
    let surface = designDocumentDirectBSplineSurfaceWithInteriorKnots()

    let featureID = try document.createBSplineSurface(
        name: "Direct Trim Control Point Weight Surface",
        surface: surface
    )
    let summary = try SurfaceSourceSummaryService().summarize(document: document)
    let faceReference = try #require(summary.sources.first?.patches.first?.faceSelectionReference)
    let trimLoop = BSplineSurfaceTrimLoop(
        role: .outer,
        edges: [
            BSplineSurfaceTrimEdge(parameterCurve: .bSpline(BSplineCurve2D(
                degree: 2,
                knots: [0.0, 0.0, 0.0, 1.0, 1.0, 1.0],
                controlPoints: [
                    Point2D(x: 0.2, y: 0.2),
                    Point2D(x: 0.52, y: 0.42),
                    Point2D(x: 0.8, y: 0.25),
                ],
                weights: [1.0, 1.2, 1.0]
            ))),
            BSplineSurfaceTrimEdge(parameterCurve: .polyline([
                SurfaceParameter(u: 0.8, v: 0.25),
                SurfaceParameter(u: 0.45, v: 0.8),
            ])),
            BSplineSurfaceTrimEdge(parameterCurve: .polyline([
                SurfaceParameter(u: 0.45, v: 0.8),
                SurfaceParameter(u: 0.2, v: 0.2),
            ])),
        ]
    )
    try document.setSurfaceTrimLoops(
        target: faceReference,
        trimLoops: [trimLoop]
    )
    let trimmedSummary = try SurfaceSourceSummaryService().summarize(document: document)
    let trimEdge = try #require(trimmedSummary.sources.first?.patches.first?.trimLoops.first?.edges.first)
    let trimReference = try #require(trimEdge.selectionReference)
    let polylineTrimReference = try #require(
        trimmedSummary.sources.first?.patches.first?.trimLoops.first?.edges.dropFirst().first?.selectionReference
    )
    let controlPoint = try #require(trimEdge.parameterCurveControlPoints.first { $0.index == 1 })
    #expect(controlPoint.weight == 1.2)
    #expect(controlPoint.isWeightEditable)

    #expect(throws: EditorError.self) {
        try document.setSurfaceTrimControlPointWeight(
            target: polylineTrimReference,
            controlPointIndex: 0,
            weight: .scalar(2.0)
        )
    }

    #expect(throws: EditorError.self) {
        try document.setSurfaceTrimControlPointWeight(
            target: trimReference,
            controlPointIndex: 1,
            weight: .scalar(0.0)
        )
    }

    try document.setSurfaceTrimControlPointWeight(
        target: trimReference,
        controlPointIndex: 1,
        weight: .scalar(2.4)
    )

    let feature = try #require(document.cadDocument.designGraph.nodes[featureID])
    guard case let .bSplineSurface(surfaceFeature) = feature.operation else {
        Issue.record("Expected a direct B-spline surface feature.")
        return
    }
    let movedLoop = try #require(surfaceFeature.trimLoops.first)
    guard case .bSpline(let movedCurve) = movedLoop.edges[0].parameterCurve else {
        Issue.record("Expected a B-spline trim parameter curve.")
        return
    }
    #expect(movedCurve.weights == [1.0, 2.4, 1.0])
    try movedLoop.validate(on: surfaceFeature.surface)

    let updatedSummary = try SurfaceSourceSummaryService().summarize(document: document)
    let updatedEdge = try #require(updatedSummary.sources.first?.patches.first?.trimLoops.first?.edges.first)
    let updatedControlPoint = try #require(
        updatedEdge.parameterCurveControlPoints.first { $0.index == 1 }
    )
    #expect(updatedControlPoint.weight == 2.4)
    #expect(updatedControlPoint.isWeightEditable)
}

@Test func directBSplineSurfaceTrimKnotInsertionRefinesAuthoredBSplinePcurveWithoutChangingShape() async throws {
    var document = DesignDocument.empty()
    let surface = designDocumentDirectBSplineSurfaceWithInteriorKnots()

    let featureID = try document.createBSplineSurface(
        name: "Direct Trim Knot Insertion Surface",
        surface: surface
    )
    let summary = try SurfaceSourceSummaryService().summarize(document: document)
    let faceReference = try #require(summary.sources.first?.patches.first?.faceSelectionReference)
    let originalCurve = BSplineCurve2D(
        degree: 2,
        knots: [0.0, 0.0, 0.0, 1.0, 1.0, 1.0],
        controlPoints: [
            Point2D(x: 0.2, y: 0.2),
            Point2D(x: 0.52, y: 0.42),
            Point2D(x: 0.8, y: 0.25),
        ],
        weights: [1.0, 1.2, 1.0]
    )
    let trimLoop = BSplineSurfaceTrimLoop(
        role: .outer,
        edges: [
            BSplineSurfaceTrimEdge(parameterCurve: .bSpline(originalCurve)),
            BSplineSurfaceTrimEdge(parameterCurve: .polyline([
                SurfaceParameter(u: 0.8, v: 0.25),
                SurfaceParameter(u: 0.45, v: 0.8),
            ])),
            BSplineSurfaceTrimEdge(parameterCurve: .polyline([
                SurfaceParameter(u: 0.45, v: 0.8),
                SurfaceParameter(u: 0.2, v: 0.2),
            ])),
        ]
    )
    try document.setSurfaceTrimLoops(
        target: faceReference,
        trimLoops: [trimLoop]
    )
    let trimmedSummary = try SurfaceSourceSummaryService().summarize(document: document)
    let trimEdge = try #require(trimmedSummary.sources.first?.patches.first?.trimLoops.first?.edges.first)
    let trimReference = try #require(trimEdge.selectionReference)
    let polylineTrimReference = try #require(
        trimmedSummary.sources.first?.patches.first?.trimLoops.first?.edges.dropFirst().first?.selectionReference
    )
    let sampleParameters = [0.0, 0.2, 0.5, 0.8, 1.0]
    let expectedPoints = try sampleParameters.map { try originalCurve.point(at: $0) }

    #expect(trimEdge.parameterCurve.kind == "bSpline")
    #expect(trimEdge.parameterCurve.degree == 2)
    #expect(trimEdge.parameterCurve.spans.map(\.lowerBound) == [0.0])
    #expect(trimEdge.parameterCurve.spans.map(\.upperBound) == [1.0])
    #expect(trimEdge.parameterCurve.supportsKnotInsertion)

    #expect(throws: EditorError.self) {
        try document.insertSurfaceTrimKnot(
            target: polylineTrimReference,
            value: .scalar(0.5)
        )
    }

    try document.insertSurfaceTrimKnot(
        target: trimReference,
        value: .scalar(0.5)
    )

    let feature = try #require(document.cadDocument.designGraph.nodes[featureID])
    guard case let .bSplineSurface(surfaceFeature) = feature.operation else {
        Issue.record("Expected a direct B-spline surface feature.")
        return
    }
    let updatedLoop = try #require(surfaceFeature.trimLoops.first)
    guard case .bSpline(let updatedCurve) = updatedLoop.edges[0].parameterCurve else {
        Issue.record("Expected a B-spline trim parameter curve.")
        return
    }
    let actualPoints = try sampleParameters.map { try updatedCurve.point(at: $0) }
    #expect(updatedCurve.knots == [0.0, 0.0, 0.0, 0.5, 1.0, 1.0, 1.0])
    #expect(updatedCurve.controlPoints.count == originalCurve.controlPoints.count + 1)
    #expect(updatedCurve.weights.count == originalCurve.weights.count + 1)
    for index in sampleParameters.indices {
        #expect(abs(actualPoints[index].x - expectedPoints[index].x) <= 1.0e-12)
        #expect(abs(actualPoints[index].y - expectedPoints[index].y) <= 1.0e-12)
    }
    try updatedLoop.validate(on: surfaceFeature.surface)

    let updatedSummary = try SurfaceSourceSummaryService().summarize(document: document)
    let updatedEdge = try #require(updatedSummary.sources.first?.patches.first?.trimLoops.first?.edges.first)
    #expect(updatedEdge.parameterCurve.knots == updatedCurve.knots)
    #expect(updatedEdge.parameterCurve.spans.count == 2)
    let insertedKnot = try #require(updatedEdge.parameterCurve.knotVector.first { $0.index == 3 })
    #expect(insertedKnot.isValueEditable)
    #expect(insertedKnot.isMultiplicityEditable)

    try document.setSurfaceTrimKnotValue(
        target: trimReference,
        knotIndex: 3,
        value: .scalar(0.4)
    )
    let retimedFeature = try #require(document.cadDocument.designGraph.nodes[featureID])
    guard case let .bSplineSurface(retimedSurfaceFeature) = retimedFeature.operation,
          let retimedLoop = retimedSurfaceFeature.trimLoops.first,
          case .bSpline(let retimedCurve) = retimedLoop.edges[0].parameterCurve else {
        Issue.record("Expected a retimed B-spline trim parameter curve.")
        return
    }
    #expect(retimedCurve.knots == [0.0, 0.0, 0.0, 0.4, 1.0, 1.0, 1.0])

    let retimedSampleParameters = [0.0, 0.2, 0.4, 0.7, 1.0]
    let retimedExpectedPoints = try retimedSampleParameters.map { try retimedCurve.point(at: $0) }
    try document.setSurfaceTrimKnotMultiplicity(
        target: trimReference,
        knotIndex: 3,
        multiplicity: 2
    )
    let saturatedFeature = try #require(document.cadDocument.designGraph.nodes[featureID])
    guard case let .bSplineSurface(saturatedSurfaceFeature) = saturatedFeature.operation,
          let saturatedLoop = saturatedSurfaceFeature.trimLoops.first,
          case .bSpline(let saturatedCurve) = saturatedLoop.edges[0].parameterCurve else {
        Issue.record("Expected a saturated B-spline trim parameter curve.")
        return
    }
    let saturatedActualPoints = try retimedSampleParameters.map { try saturatedCurve.point(at: $0) }
    #expect(saturatedCurve.knots == [0.0, 0.0, 0.0, 0.4, 0.4, 1.0, 1.0, 1.0])
    for index in retimedSampleParameters.indices {
        #expect(abs(saturatedActualPoints[index].x - retimedExpectedPoints[index].x) <= 1.0e-12)
        #expect(abs(saturatedActualPoints[index].y - retimedExpectedPoints[index].y) <= 1.0e-12)
    }
}

@Test func surfaceSpanSplitRejectsGeneratedPolySplineSpanReference() async throws {
    var document = DesignDocument.empty()
    let featureID = try document.createPolySplineSurface(
        name: "Unsupported PolySpline Span Split Surface",
        sourceMesh: designDocumentPolySplineQuadMesh()
    )
    let summary = try SurfaceSourceSummaryService().summarize(document: document)
    let patch = try #require(summary.sources.first?.patches.first)
    let summarySpan = try #require(patch.basis.uSpans.first)
    #expect(summarySpan.isEditable == false)
    #expect(summarySpan.selectionReference == nil)
    let spanReference = SelectionReference.surface(.span(SurfaceSpanReference(
        surface: SurfaceReference(
            faceName: PersistentName(components: [
                .feature(featureID),
                .generated("polySpline"),
                .subshape("patch:\(patch.patchID):face"),
            ])
        ),
        direction: .u,
        spanIndex: summarySpan.index
    )))

    #expect(throws: EditorError.self) {
        try document.splitSurfaceSpan(
            target: spanReference,
            fraction: .scalar(0.5)
        )
    }
    let feature = try #require(document.cadDocument.designGraph.nodes[featureID])
    guard case .polySpline = feature.operation else {
        Issue.record("Rejected PolySpline span split must not mutate the source feature.")
        return
    }
}

@Test func directBSplineSurfaceKnotReferenceInsertsDuplicateKnotMultiplicity() async throws {
    var document = DesignDocument.empty()
    let surface = designDocumentDirectBSplineSurfaceWithInteriorKnots()

    let featureID = try document.createBSplineSurface(
        name: "Direct Multiplicity Knot Surface",
        surface: surface
    )
    let summary = try SurfaceSourceSummaryService().summarize(document: document)
    let patch = try #require(summary.sources.first?.patches.first)
    let editableKnot = try #require(patch.basis.uKnotVector.first { $0.index == 3 })
    #expect(editableKnot.value == 0.5)
    #expect(editableKnot.isEditable)
    let knotReference = try #require(editableKnot.selectionReference)

    try document.insertSurfaceKnot(
        target: knotReference,
        value: .scalar(0.5)
    )

    let feature = try #require(document.cadDocument.designGraph.nodes[featureID])
    guard case let .bSplineSurface(surfaceFeature) = feature.operation else {
        Issue.record("Expected a direct B-spline surface feature.")
        return
    }
    #expect(surfaceFeature.surface.uKnots == [0.0, 0.0, 0.0, 0.5, 0.5, 1.0, 1.0, 1.0])
    #expect(surfaceFeature.surface.uControlPointCount == surface.uControlPointCount + 1)
    for u in [0.0, 0.2, 0.5, 0.8, 1.0] {
        for v in [0.0, 0.3, 0.6, 1.0] {
            let before = try surface.point(u: u, v: v)
            let after = try surfaceFeature.surface.point(u: u, v: v)
            #expect(abs(before.x - after.x) <= 1.0e-10)
            #expect(abs(before.y - after.y) <= 1.0e-10)
            #expect(abs(before.z - after.z) <= 1.0e-10)
        }
    }
    #expect(throws: EditorError.self) {
        try document.insertSurfaceKnot(
            target: knotReference,
            value: .scalar(0.45)
        )
    }
}

@Test func directBSplineSurfaceKnotReferenceSetsExplicitKnotMultiplicity() async throws {
    var document = DesignDocument.empty()
    let surface = designDocumentDirectBSplineSurfaceWithInteriorKnots()

    let featureID = try document.createBSplineSurface(
        name: "Direct Explicit Multiplicity Surface",
        surface: surface
    )
    let summary = try SurfaceSourceSummaryService().summarize(document: document)
    let patch = try #require(summary.sources.first?.patches.first)
    let editableKnot = try #require(patch.basis.uKnotVector.first { $0.index == 3 })
    #expect(editableKnot.value == 0.5)
    #expect(editableKnot.multiplicity == 1)
    #expect(editableKnot.isEditable)
    let knotReference = try #require(editableKnot.selectionReference)

    try document.setSurfaceKnotMultiplicity(
        target: knotReference,
        multiplicity: 2
    )

    let feature = try #require(document.cadDocument.designGraph.nodes[featureID])
    guard case let .bSplineSurface(surfaceFeature) = feature.operation else {
        Issue.record("Expected a direct B-spline surface feature.")
        return
    }
    #expect(surfaceFeature.surface.uKnots == [0.0, 0.0, 0.0, 0.5, 0.5, 1.0, 1.0, 1.0])
    #expect(surfaceFeature.surface.vKnots == surface.vKnots)
    #expect(surfaceFeature.surface.uControlPointCount == surface.uControlPointCount + 1)
    #expect(surfaceFeature.surface.vControlPointCount == surface.vControlPointCount)
    for u in [0.0, 0.2, 0.5, 0.8, 1.0] {
        for v in [0.0, 0.3, 0.6, 1.0] {
            let before = try surface.point(u: u, v: v)
            let after = try surfaceFeature.surface.point(u: u, v: v)
            #expect(abs(before.x - after.x) <= 1.0e-10)
            #expect(abs(before.y - after.y) <= 1.0e-10)
            #expect(abs(before.z - after.z) <= 1.0e-10)
        }
    }

    let updatedSummary = try SurfaceSourceSummaryService().summarize(document: document)
    let repeatedKnots = try #require(
        updatedSummary.sources.first?.patches.first?.basis.uKnotVector.filter { $0.value == 0.5 }
    )
    #expect(repeatedKnots.count == 2)
    #expect(repeatedKnots.allSatisfy { $0.multiplicity == 2 })
    #expect(repeatedKnots.allSatisfy { $0.isEditable })

    let boundaryKnot = try #require(patch.basis.uKnotVector.first { $0.index == 0 })
    let boundaryReference = try #require(boundaryKnot.selectionReference)
    #expect(throws: EditorError.self) {
        try document.setSurfaceKnotMultiplicity(
            target: boundaryReference,
            multiplicity: 2
        )
    }
    #expect(throws: EditorError.self) {
        try document.setSurfaceKnotMultiplicity(
            target: knotReference,
            multiplicity: 2
        )
    }
    #expect(throws: EditorError.self) {
        try document.setSurfaceKnotMultiplicity(
            target: knotReference,
            multiplicity: 3
        )
    }
}

@Test func directBSplineSurfaceTrimReferenceMatchesBoundaryContinuity() async throws {
    var document = DesignDocument.empty()
    let referenceSurface = designDocumentDirectBSplineSurface()
    let targetSurface = designDocumentOffsetDirectBSplineSurface()

    let referenceFeatureID = try document.createBSplineSurface(
        name: "Reference Boundary Surface",
        surface: referenceSurface
    )
    let targetFeatureID = try document.createBSplineSurface(
        name: "Target Boundary Surface",
        surface: targetSurface
    )
    let referenceTrim = try designDocumentSurfaceTrimReference(
        featureID: referenceFeatureID,
        edgeIndex: 2,
        in: document
    )
    let targetTrim = try designDocumentSurfaceTrimReference(
        featureID: targetFeatureID,
        edgeIndex: 0,
        in: document
    )

    try document.matchSurfaceBoundaryContinuity(
        target: targetTrim,
        reference: referenceTrim,
        level: .g2,
        matchSide: .opposite,
        referenceDirection: .forward
    )

    let matchedFeature = try #require(document.cadDocument.designGraph.nodes[targetFeatureID])
    let referenceFeature = try #require(document.cadDocument.designGraph.nodes[referenceFeatureID])
    guard case let .bSplineSurface(matchedSurfaceFeature) = matchedFeature.operation,
          case let .bSplineSurface(referenceSurfaceFeature) = referenceFeature.operation else {
        Issue.record("Expected direct B-spline surface features.")
        return
    }
    let matchedSurface = matchedSurfaceFeature.surface
    let storedReferenceSurface = referenceSurfaceFeature.surface
    for uIndex in 0..<matchedSurface.uControlPointCount {
        let boundary = designDocumentHomogeneousControlPoint(
            storedReferenceSurface,
            vIndex: 3,
            uIndex: uIndex
        )
        let firstInward = designDocumentHomogeneousControlPoint(
            storedReferenceSurface,
            vIndex: 2,
            uIndex: uIndex
        )
        let secondInward = designDocumentHomogeneousControlPoint(
            storedReferenceSurface,
            vIndex: 1,
            uIndex: uIndex
        )
        let referenceFirstDerivativeScale = 3.0
        let targetFirstDerivativeScale = 3.0 / 2.0
        let referenceSecondDerivativeScale = 6.0
        let targetSecondDerivativeScale = 6.0 / 4.0
        let referenceFirstDerivative = (firstInward - boundary) * referenceFirstDerivativeScale
        let expectedFirstInward = boundary
            + (referenceFirstDerivative * -1.0) / targetFirstDerivativeScale
        let referenceSecondDifference = secondInward - firstInward * 2.0 + boundary
        let referenceSecondDerivative = referenceSecondDifference * referenceSecondDerivativeScale
        let expectedSecondInward = (referenceSecondDerivative / targetSecondDerivativeScale)
            + expectedFirstInward * 2.0
            - boundary
        let expectedBoundary = try boundary.dehomogenized()
        let expectedFirst = try expectedFirstInward.dehomogenized()
        let expectedSecond = try expectedSecondInward.dehomogenized()
        #expect(matchedSurface.controlPoints[0][uIndex].isApproximatelyEqual(
            to: expectedBoundary.point,
            tolerance: 1.0e-12
        ))
        #expect(
            matchedSurface.controlPoints[1][uIndex].isApproximatelyEqual(
                to: expectedFirst.point,
                tolerance: 1.0e-12
            )
        )
        #expect(
            matchedSurface.controlPoints[2][uIndex].isApproximatelyEqual(
                to: expectedSecond.point,
                tolerance: 1.0e-12
            )
        )
        #expect(matchedSurface.weights[0][uIndex] == expectedBoundary.weight)
        #expect(matchedSurface.weights[1][uIndex] == expectedFirst.weight)
        #expect(matchedSurface.weights[2][uIndex] == expectedSecond.weight)
    }
    for u in [0.25, 0.5, 0.75] {
        let matchedGeometry = try matchedSurface.differentialGeometry(atU: u, v: 0.0)
        let referenceGeometry = try storedReferenceSurface.differentialGeometry(atU: u, v: 1.0)
        #expect(matchedGeometry.position.isApproximatelyEqual(
            to: referenceGeometry.position,
            tolerance: 1.0e-12
        ))
        #expect((matchedGeometry.tangentV - referenceGeometry.tangentV).length <= 1.0e-10)
        #expect(
            (
                matchedGeometry.secondDerivativeVV
                    - referenceGeometry.secondDerivativeVV
            ).length <= 1.0e-9
        )
    }

    let updatedSummary = try SurfaceSourceSummaryService().summarize(document: document)
    let updatedTargetSource = try #require(
        updatedSummary.sources.first { $0.featureID == targetFeatureID.description }
    )
    #expect(updatedTargetSource.patches.first?.trimLoops.first?.selectionReferences.count == 4)

    #expect(throws: EditorError.self) {
        try document.matchSurfaceBoundaryContinuity(
            target: targetTrim,
            reference: targetTrim,
            level: .g0
        )
    }

    let polySplineFeatureID = try document.createPolySplineSurface(
        name: "Unsupported PolySpline Boundary",
        sourceMesh: designDocumentPolySplineQuadMesh()
    )
    let polySplineTrim = try designDocumentSurfaceTrimReference(
        featureID: polySplineFeatureID,
        edgeIndex: 0,
        in: document
    )
    #expect(throws: EditorError.self) {
        try document.matchSurfaceBoundaryContinuity(
            target: targetTrim,
            reference: polySplineTrim,
            level: .g0
        )
    }

    let unclampedFeatureID = try document.createBSplineSurface(
        name: "Unclamped Boundary Surface",
        surface: designDocumentUnclampedDirectBSplineSurface()
    )
    let unclampedTrim = try designDocumentSurfaceTrimReference(
        featureID: unclampedFeatureID,
        edgeIndex: 0,
        in: document
    )
    #expect(throws: EditorError.self) {
        try document.matchSurfaceBoundaryContinuity(
            target: unclampedTrim,
            reference: referenceTrim,
            level: .g1
        )
    }
}

@Test func directBSplineSurfaceBoundaryContinuityCompatibilityReportsPairContract() async throws {
    var document = DesignDocument.empty()
    let referenceFeatureID = try document.createBSplineSurface(
        name: "Reference Compatibility Surface",
        surface: designDocumentDirectBSplineSurface()
    )
    let targetFeatureID = try document.createBSplineSurface(
        name: "Target Compatibility Surface",
        surface: designDocumentOffsetDirectBSplineSurface()
    )
    let referenceTrim = try designDocumentSurfaceTrimReference(
        featureID: referenceFeatureID,
        edgeIndex: 2,
        in: document
    )
    let targetTrim = try designDocumentSurfaceTrimReference(
        featureID: targetFeatureID,
        edgeIndex: 0,
        in: document
    )

    let compatibility = try document.surfaceBoundaryContinuityCompatibility(
        target: targetTrim,
        reference: referenceTrim
    )

    #expect(compatibility.status == .compatible)
    #expect(compatibility.supportedContinuityLevels == [.g0, .g1, .g2])
    #expect(compatibility.maximumSupportedContinuityLevel == .g2)
    #expect(compatibility.recommendedReferenceDirection == .forward)
    #expect(compatibility.recommendedMatchSide == .opposite)
    #expect(compatibility.target.featureID == targetFeatureID)
    #expect(compatibility.reference.featureID == referenceFeatureID)
    #expect(compatibility.target.role == "vMin")
    #expect(compatibility.reference.role == "vMax")
    #expect(compatibility.target.boundaryControlPointCount == 4)
    #expect(compatibility.reference.boundaryControlPointCount == 4)
    #expect(compatibility.diagnostics.contains { $0.code == "compatibleBoundaryPair" })

    let sameBoundary = try document.surfaceBoundaryContinuityCompatibility(
        target: targetTrim,
        reference: targetTrim
    )
    #expect(sameBoundary.status == .incompatible)
    #expect(sameBoundary.supportedContinuityLevels.isEmpty)
    #expect(sameBoundary.recommendedReferenceDirection == nil)
    #expect(sameBoundary.recommendedMatchSide == nil)
    #expect(sameBoundary.diagnostics.contains { $0.code == "sameBoundary" })

    let unclampedFeatureID = try document.createBSplineSurface(
        name: "Unclamped Compatibility Surface",
        surface: designDocumentUnclampedDirectBSplineSurface()
    )
    let unclampedTrim = try designDocumentSurfaceTrimReference(
        featureID: unclampedFeatureID,
        edgeIndex: 0,
        in: document
    )
    let unclamped = try document.surfaceBoundaryContinuityCompatibility(
        target: unclampedTrim,
        reference: referenceTrim
    )
    #expect(unclamped.status == .incompatible)
    #expect(unclamped.recommendedReferenceDirection == nil)
    #expect(unclamped.recommendedMatchSide == nil)
    #expect(unclamped.diagnostics.contains { $0.code == "unclampedBoundary" })
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

@Test func objectDimensionSummaryExposesDocumentDisplayValues() async throws {
    var document = DesignDocument.empty()
    document.setDisplayUnit(.centimeter)
    try document.createExtrudedRectangle(
        name: "Dimension Summary Display Box",
        plane: .xy,
        width: .length(2.0, .meter),
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

    let sizeX = try #require(summary.entries.first { $0.kind == .sizeX })
    #expect(summary.displayUnit == .centimeter)
    #expect(summary.displayUnitSymbol == "cm")
    #expect(sizeX.valueKind == .length)
    #expect(abs(sizeX.resolvedMeters - 2.0) < 1.0e-12)
    #expect(abs(sizeX.resolvedDisplayValue - 200.0) < 1.0e-12)
    #expect(sizeX.resolvedDisplayUnitSymbol == "cm")
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
    try document.setRulerConfiguration(.standard(for: .centimeter))
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
@Test func documentExportServiceNormalizesKilometerThreeMFExportToMeters() async throws {
    let temporaryDirectory = try makeTemporaryDirectory()
    defer {
        removeTemporaryDirectory(temporaryDirectory)
    }

    let preset = ExportPreset(
        name: "Site 3MF",
        format: .threeMF,
        outputUnit: .kilometer,
        destinationPolicy: .overwrite
    )
    var metadata = ProductMetadata.empty()
    metadata.exportPresets = [preset.id: preset]
    var document = DesignDocument.empty(named: "Site Export")
    try document.setRulerConfiguration(WorkspaceScalePreset.sitePlanning.rulerConfiguration)
    document.productMetadata = metadata
    let session = EditorSession(document: document)
    _ = try session.execute(
        .createExtrudedRectangle(
            name: "Site Box",
            plane: .xy,
            width: .length(1.0, .kilometer),
            height: .length(0.5, .kilometer),
            depth: .length(0.1, .kilometer),
            direction: .normal
        )
    )

    let outputURL = temporaryDirectory.appendingPathComponent("site-box.3mf")
    let result = try DocumentExportService().export(
        document: session.document,
        generation: session.generation,
        to: outputURL,
        options: ExportOptions(presetName: "Site 3MF")
    )
    let imported = try ThreeMFExchange().import(try Data(contentsOf: outputURL))
    let bounds = try meshBounds(imported.meshes.values.flatMap(\.positions))

    #expect(result.format == .threeMF)
    #expect(result.presetName == "Site 3MF")
    #expect(result.outputUnit == .meter)
    #expect(imported.units.length == .meter)
    #expect(result.diagnostics.contains { diagnostic in
        diagnostic.severity == .info
            && diagnostic.message.contains("3MF does not support kilometer units")
    })
    #expect(approximatelyEqual(bounds.width, 1_000.0))
    #expect(approximatelyEqual(bounds.height, 500.0))
    #expect(approximatelyEqual(bounds.depth, 100.0))
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

private func meshBounds(
    _ points: [Point3D]
) throws -> (width: Double, height: Double, depth: Double) {
    let first = try #require(points.first)
    let bounds = points.dropFirst().reduce(
        (
            minX: first.x,
            maxX: first.x,
            minY: first.y,
            maxY: first.y,
            minZ: first.z,
            maxZ: first.z
        )
    ) { bounds, point in
        (
            minX: min(bounds.minX, point.x),
            maxX: max(bounds.maxX, point.x),
            minY: min(bounds.minY, point.y),
            maxY: max(bounds.maxY, point.y),
            minZ: min(bounds.minZ, point.z),
            maxZ: max(bounds.maxZ, point.z)
        )
    }
    return (
        width: bounds.maxX - bounds.minX,
        height: bounds.maxY - bounds.minY,
        depth: bounds.maxZ - bounds.minZ
    )
}

private func approximatelyEqual(
    _ lhs: Double,
    _ rhs: Double,
    tolerance: Double = 1.0e-9
) -> Bool {
    abs(lhs - rhs) <= tolerance
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

private func designDocumentDirectBSplineSurface() -> BSplineSurface3D {
    let base = BSplineSurface3D.cubicBezierPatch(
        bottomLeft: Point3D(x: 0.0, y: 0.0, z: 0.0),
        bottomRight: Point3D(x: 0.02, y: 0.0, z: 0.0),
        topRight: Point3D(x: 0.02, y: 0.02, z: 0.0),
        topLeft: Point3D(x: 0.0, y: 0.02, z: 0.0)
    )
    var weights = base.weights
    weights[1][1] = 2.0
    return BSplineSurface3D(
        uDegree: base.uDegree,
        vDegree: base.vDegree,
        uKnots: base.uKnots,
        vKnots: base.vKnots,
        controlPoints: base.controlPoints,
        weights: weights
    )
}

private func designDocumentOffsetDirectBSplineSurface() -> BSplineSurface3D {
    let base = BSplineSurface3D.cubicBezierPatch(
        bottomLeft: Point3D(x: 0.0, y: 0.04, z: 0.004),
        bottomRight: Point3D(x: 0.02, y: 0.04, z: -0.002),
        topRight: Point3D(x: 0.02, y: 0.06, z: 0.003),
        topLeft: Point3D(x: 0.0, y: 0.06, z: 0.001)
    )
    var weights = base.weights
    weights[0][1] = 1.2
    weights[1][1] = 1.4
    weights[2][1] = 1.6
    return BSplineSurface3D(
        uDegree: base.uDegree,
        vDegree: base.vDegree,
        uKnots: base.uKnots,
        vKnots: [0.0, 0.0, 0.0, 0.0, 2.0, 2.0, 2.0, 2.0],
        controlPoints: base.controlPoints,
        weights: weights
    )
}

private func designDocumentUnclampedDirectBSplineSurface() -> BSplineSurface3D {
    let base = designDocumentDirectBSplineSurface()
    return BSplineSurface3D(
        uDegree: base.uDegree,
        vDegree: base.vDegree,
        uKnots: [-1.0, 0.0, 0.0, 0.0, 1.0, 1.0, 1.0, 2.0],
        vKnots: [-1.0, 0.0, 0.0, 0.0, 1.0, 1.0, 1.0, 2.0],
        controlPoints: base.controlPoints,
        weights: base.weights
    )
}

private struct DesignDocumentHomogeneousControlPoint {
    var point: Vector3D
    var weight: Double

    init(point: Point3D, weight: Double) {
        self.point = Vector3D(
            x: point.x * weight,
            y: point.y * weight,
            z: point.z * weight
        )
        self.weight = weight
    }

    func dehomogenized() throws -> (point: Point3D, weight: Double) {
        guard weight.isFinite, weight > Double.ulpOfOne, point.isFinite else {
            throw GeometryError.invalidDistance(weight)
        }
        let vector = point / weight
        guard vector.isFinite else {
            throw GeometryError.invalidCoordinate(vector.x)
        }
        return (
            Point3D(x: vector.x, y: vector.y, z: vector.z),
            weight
        )
    }

    static func + (
        lhs: DesignDocumentHomogeneousControlPoint,
        rhs: DesignDocumentHomogeneousControlPoint
    ) -> DesignDocumentHomogeneousControlPoint {
        DesignDocumentHomogeneousControlPoint(
            point: lhs.point + rhs.point,
            weight: lhs.weight + rhs.weight
        )
    }

    static func - (
        lhs: DesignDocumentHomogeneousControlPoint,
        rhs: DesignDocumentHomogeneousControlPoint
    ) -> DesignDocumentHomogeneousControlPoint {
        DesignDocumentHomogeneousControlPoint(
            point: lhs.point - rhs.point,
            weight: lhs.weight - rhs.weight
        )
    }

    static func * (
        lhs: DesignDocumentHomogeneousControlPoint,
        rhs: Double
    ) -> DesignDocumentHomogeneousControlPoint {
        DesignDocumentHomogeneousControlPoint(
            point: lhs.point * rhs,
            weight: lhs.weight * rhs
        )
    }

    static func / (
        lhs: DesignDocumentHomogeneousControlPoint,
        rhs: Double
    ) -> DesignDocumentHomogeneousControlPoint {
        DesignDocumentHomogeneousControlPoint(
            point: lhs.point / rhs,
            weight: lhs.weight / rhs
        )
    }

    private init(point: Vector3D, weight: Double) {
        self.point = point
        self.weight = weight
    }
}

private func designDocumentHomogeneousControlPoint(
    _ surface: BSplineSurface3D,
    vIndex: Int,
    uIndex: Int
) -> DesignDocumentHomogeneousControlPoint {
    DesignDocumentHomogeneousControlPoint(
        point: surface.controlPoints[vIndex][uIndex],
        weight: surface.weights[vIndex][uIndex]
    )
}

private func designDocumentDirectBSplineSurfaceWithInteriorKnots() -> BSplineSurface3D {
    let base = BSplineSurface3D.cubicBezierPatch(
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
        controlPoints: base.controlPoints,
        weights: base.weights
    )
}

private func designDocumentSurfaceTrimReference(
    featureID: FeatureID,
    edgeIndex: Int,
    in document: DesignDocument
) throws -> SelectionReference {
    let summary = try SurfaceSourceSummaryService().summarize(document: document)
    let source = try #require(summary.sources.first { $0.featureID == featureID.description })
    let trimLoop = try #require(source.patches.first?.trimLoops.first)
    guard trimLoop.selectionReferences.indices.contains(edgeIndex) else {
        throw EditorError(
            code: .referenceUnresolved,
            message: "Test surface trim reference is missing."
        )
    }
    return trimLoop.selectionReferences[edgeIndex]
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
