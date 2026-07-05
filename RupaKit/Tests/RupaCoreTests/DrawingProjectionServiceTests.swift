import SwiftCAD
import Testing
@testable import RupaCore

@MainActor
@Test func drawingProjectionGeneratesSavedViewStrokesWithoutFaceDiagonals() throws {
    let session = EditorSession()
    _ = try session.execute(
        .createExtrudedRectangle(
            name: "Drawing Box",
            plane: .xy,
            width: .length(2.0, .meter),
            height: .length(2.0, .meter),
            depth: .length(2.0, .meter),
            direction: .normal
        )
    )
    let savedView = SavedView(
        name: "Drawing View",
        camera: SavedViewCamera(
            target: .origin,
            distanceMeters: 6.0,
            yawRadians: .pi / 4.0,
            pitchRadians: 0.62
        ),
        projection: .orthographic(heightMeters: 6.0),
        displayScale: SavedViewDisplayScale(ruler: .standard(for: .meter))
    )
    _ = try session.execute(.createSavedView(savedView))

    let result = try DrawingProjectionService().generate(
        document: session.document,
        query: DrawingProjectionQuery(savedViewID: savedView.id),
        objectRegistry: session.objectRegistry,
        currentEvaluation: session.currentEvaluation,
        currentGeneration: session.generation
    )

    #expect(result.savedViewID == savedView.id)
    #expect(result.savedViewName == "Drawing View")
    #expect(result.projectionMode == .orthographic)
    #expect(result.bodyCount == 1)
    #expect(result.triangleCount == 12)
    #expect(result.strokeCount == 12)
    #expect(result.strokes.allSatisfy { $0.kind == .crease })
    #expect(result.unclassifiedStrokeCount == 0)
    #expect(result.visibilitySegmentCount >= result.strokeCount)
    #expect(result.visibleSegmentCount > 0)
    #expect(result.hiddenSegmentCount > 0)
    #expect(result.unclassifiedSegmentCount == 0)
    #expect(
        result.visibleStrokeCount
            + result.hiddenStrokeCount
            + result.partiallyHiddenStrokeCount
            + result.unclassifiedStrokeCount == result.strokeCount
    )
    #expect(
        result.visibleSegmentCount
            + result.hiddenSegmentCount
            + result.partiallyHiddenSegmentCount
            + result.unclassifiedSegmentCount == result.visibilitySegmentCount
    )
    #expect(result.strokes.allSatisfy { $0.visibility != .unclassified })
    #expect(result.strokes.allSatisfy { $0.visibilitySegments.isEmpty == false })
    #expect(result.strokes.flatMap(\.visibilitySegments).allSatisfy { segment in
        segment.visibility != .unclassified
            && segment.startFraction >= 0.0
            && segment.endFraction <= 1.0
            && segment.endFraction > segment.startFraction
            && segment.lengthMeters > 0.0
    })
    #expect(result.strokes.allSatisfy { $0.lengthMeters > 0.0 })
    #expect(result.bounds != nil)
    #expect(result.diagnostics.contains {
        $0.message.contains("hidden-line classified")
    })
    #expect(result.diagnostics.contains {
        $0.message.contains("visibility segment")
    })
}

@MainActor
@Test func drawingProjectionGeneratesSectionContoursAndHatchesFromSavedViewSectionState() throws {
    let session = EditorSession()
    _ = try session.execute(
        .createExtrudedRectangle(
            name: "Sectioned Drawing Box",
            plane: .xy,
            width: .length(2.0, .meter),
            height: .length(2.0, .meter),
            depth: .length(2.0, .meter),
            direction: .normal
        )
    )
    var document = session.document
    let sectionNodeID = try document.createSectionPlane(name: "Mid Height Section")
    try document.setSceneNodeTransform(
        id: sectionNodeID,
        localTransform: Transform3D(
            matrix: try Matrix4x4(values: [
                1.0, 0.0, 0.0, 0.0,
                0.0, 1.0, 0.0, 0.0,
                0.0, 0.0, 1.0, 0.0,
                0.0, 0.0, 1.0, 1.0,
            ])
        )
    )
    let savedView = SavedView(
        name: "Section Drawing View",
        camera: SavedViewCamera(
            target: Point3D(x: 0.0, y: 0.0, z: 1.0),
            distanceMeters: 6.0,
            yawRadians: .pi / 4.0,
            pitchRadians: 0.62
        ),
        projection: .orthographic(heightMeters: 6.0),
        sectionState: SavedViewSectionState(sectionSceneNodeIDs: [sectionNodeID]),
        displayScale: SavedViewDisplayScale(ruler: .standard(for: .meter))
    )
    _ = try document.createSavedView(savedView, objectRegistry: session.objectRegistry)

    let result = try DrawingProjectionService().generate(
        document: document,
        query: DrawingProjectionQuery(savedViewID: savedView.id),
        objectRegistry: session.objectRegistry,
        currentEvaluation: session.currentEvaluation,
        currentGeneration: session.generation
    )

    #expect(result.sectionContourCount > 0)
    #expect(result.sectionHatchSegmentCount > 0)
    #expect(result.sectionContours.allSatisfy { $0.sectionSourceID == sectionNodeID.description })
    #expect(result.sectionHatches.allSatisfy { $0.sectionSourceID == sectionNodeID.description })
    #expect(result.sectionHatches.allSatisfy { $0.lengthMeters > 0.0 })
    #expect(result.sectionHatches.allSatisfy { $0.spacingMeters > 0.0 })
    #expect(result.sectionHatches.allSatisfy { $0.angleDegrees == 45.0 })
    #expect(result.truncatedSectionHatches == false)
    #expect(result.bounds != nil)
    #expect(result.diagnostics.contains {
        $0.message.contains("section contour")
            && $0.message.contains("section hatch")
    })
}

@MainActor
@Test func drawingProjectionTruncatesAtRequestedStrokeLimit() throws {
    let session = EditorSession()
    _ = try session.execute(
        .createExtrudedRectangle(
            name: "Drawing Box",
            plane: .xy,
            width: .length(2.0, .meter),
            height: .length(2.0, .meter),
            depth: .length(2.0, .meter),
            direction: .normal
        )
    )
    let savedView = SavedView(
        name: "Limited View",
        camera: SavedViewCamera(
            target: .origin,
            distanceMeters: 6.0,
            yawRadians: .pi / 4.0,
            pitchRadians: 0.62
        ),
        projection: .orthographic(heightMeters: 6.0),
        displayScale: SavedViewDisplayScale(ruler: .standard(for: .meter))
    )
    _ = try session.execute(.createSavedView(savedView))

    let result = try DrawingProjectionService().generate(
        document: session.document,
        query: DrawingProjectionQuery(
            savedViewID: savedView.id,
            maximumStrokeCount: 3
        ),
        objectRegistry: session.objectRegistry,
        currentEvaluation: session.currentEvaluation,
        currentGeneration: session.generation
    )

    #expect(result.strokeCount == 3)
    #expect(result.visibilitySegmentCount >= result.strokeCount)
    #expect(
        result.visibleStrokeCount
            + result.hiddenStrokeCount
            + result.partiallyHiddenStrokeCount
            + result.unclassifiedStrokeCount == result.strokeCount
    )
    #expect(
        result.visibleSegmentCount
            + result.hiddenSegmentCount
            + result.partiallyHiddenSegmentCount
            + result.unclassifiedSegmentCount == result.visibilitySegmentCount
    )
    #expect(result.unclassifiedStrokeCount == 0)
    #expect(result.unclassifiedSegmentCount == 0)
    #expect(result.truncatedStrokes)
    #expect(result.diagnostics.contains {
        $0.message.contains("truncated")
    })
}

@MainActor
@Test func drawingProjectionSplitsPartiallyHiddenStrokesIntoVisibilitySegments() throws {
    let session = EditorSession()
    _ = try session.execute(
        .createExtrudedRectangleFromCorners(
            name: "Back Rail",
            plane: .xy,
            firstCorner: drawingProjectionSketchPoint(x: -2.0, y: -0.1),
            oppositeCorner: drawingProjectionSketchPoint(x: 2.0, y: 0.1),
            depth: .length(0.1, .meter),
            direction: .normal
        )
    )
    _ = try session.execute(
        .createExtrudedRectangleFromCorners(
            name: "Occluder",
            plane: .xy,
            firstCorner: drawingProjectionSketchPoint(x: -0.5, y: -0.5),
            oppositeCorner: drawingProjectionSketchPoint(x: 0.5, y: 0.5),
            depth: .length(1.0, .meter),
            direction: .normal
        )
    )
    let savedView = SavedView(
        name: "Split View",
        camera: SavedViewCamera(
            target: Point3D(x: 0.0, y: 0.0, z: 0.5),
            distanceMeters: 6.0,
            yawRadians: 0.0,
            pitchRadians: 0.08
        ),
        projection: .orthographic(heightMeters: 5.0),
        displayScale: SavedViewDisplayScale(ruler: .standard(for: .meter))
    )
    _ = try session.execute(.createSavedView(savedView))

    let result = try DrawingProjectionService().generate(
        document: session.document,
        query: DrawingProjectionQuery(savedViewID: savedView.id),
        objectRegistry: session.objectRegistry,
        currentEvaluation: session.currentEvaluation,
        currentGeneration: session.generation
    )

    let splitStroke = try #require(result.strokes.first { stroke in
        stroke.visibility == .partiallyHidden
            && stroke.visibilitySegments.contains { $0.visibility == .visible }
            && stroke.visibilitySegments.contains { $0.visibility == .hidden }
    })
    #expect(result.partiallyHiddenStrokeCount > 0)
    #expect(result.visibilitySegmentCount > result.strokeCount)
    #expect(result.visibleSegmentCount > 0)
    #expect(result.hiddenSegmentCount > 0)
    #expect(result.unclassifiedSegmentCount == 0)
    #expect(splitStroke.visibilitySegments.count > 1)
    #expect(splitStroke.visibilitySegments.allSatisfy { segment in
        segment.startFraction >= 0.0
            && segment.endFraction <= 1.0
            && segment.endFraction > segment.startFraction
            && segment.lengthMeters > 0.0
    })
}

@MainActor
@Test func drawingProjectionGeneratesDrawingAnnotationsFromMeasurementMetadataWithoutBodies() throws {
    let session = EditorSession()
    var document = session.document
    try document.setRulerConfiguration(.standard(for: .meter))
    let measurementID = try document.addMeasurementAnnotation(
        MeasurementAnnotation(
            name: "Overall Width",
            kind: .distance,
            anchors: [
                .worldPoint(Point3D(x: -1.0, y: 0.0, z: 0.0), role: .start),
                .worldPoint(Point3D(x: 1.0, y: 0.0, z: 0.0), role: .end),
            ],
            labelPosition: Point3D(x: 0.0, y: 0.25, z: 0.0)
        ),
        objectRegistry: session.objectRegistry
    )
    let savedView = SavedView(
        name: "Annotated Drawing View",
        camera: SavedViewCamera(
            target: .origin,
            distanceMeters: 4.0,
            yawRadians: 0.0,
            pitchRadians: 0.0
        ),
        projection: .orthographic(heightMeters: 4.0),
        displayScale: SavedViewDisplayScale(ruler: .standard(for: .meter))
    )
    _ = try document.createSavedView(savedView, objectRegistry: session.objectRegistry)

    let result = try DrawingProjectionService().generate(
        document: document,
        query: DrawingProjectionQuery(savedViewID: savedView.id),
        objectRegistry: session.objectRegistry,
        currentEvaluation: session.currentEvaluation,
        currentGeneration: session.generation
    )

    let annotation = try #require(result.annotations.first)
    #expect(result.bodyCount == 0)
    #expect(result.strokeCount == 0)
    #expect(result.annotationCount == 1)
    #expect(annotation.measurementID == measurementID)
    #expect(annotation.name == "Overall Width")
    #expect(annotation.kind == .distance)
    #expect(annotation.anchors.count == 2)
    #expect(annotation.measurementMeters == 2.0)
    #expect(annotation.displayText == "2 m")
    #expect(annotation.labelLayout?.placement == .manual)
    let labelBounds = try #require(annotation.labelLayout?.bounds2D)
    #expect(drawingProjectionPointApproximatelyEqual(
        annotation.labelPoint2D,
        Point2D(x: 0.0, y: -0.25),
        tolerance: 1.0e-3
    ))
    #expect(drawingProjectionPointApproximatelyEqual(
        drawingProjectionBoundsCenter(labelBounds),
        annotation.labelPoint2D
    ))
    #expect(result.bounds != nil)
    #expect(result.diagnostics.contains {
        $0.message.contains("drawing annotation")
    })
}

@MainActor
@Test func drawingProjectionAdjustsAutomaticAnnotationLabelsToAvoidOverlap() throws {
    let result = try drawingProjectionResultWithMeasurements([
        MeasurementAnnotation(
            name: "A Width",
            kind: .distance,
            anchors: [
                .worldPoint(Point3D(x: -0.6, y: 0.0, z: 0.0), role: .start),
                .worldPoint(Point3D(x: 0.6, y: 0.0, z: 0.0), role: .end),
            ]
        ),
        MeasurementAnnotation(
            name: "B Width",
            kind: .distance,
            anchors: [
                .worldPoint(Point3D(x: -0.6, y: 0.02, z: 0.0), role: .start),
                .worldPoint(Point3D(x: 0.6, y: 0.02, z: 0.0), role: .end),
            ]
        ),
    ])

    let annotations = result.annotations.sorted { $0.name < $1.name }
    let first = try #require(annotations.first)
    let second = try #require(annotations.dropFirst().first)
    let firstBounds = try #require(first.labelLayout?.bounds2D)
    let secondBounds = try #require(second.labelLayout?.bounds2D)

    #expect(result.annotationCount == 2)
    #expect(first.labelLayout?.placement == .automatic)
    #expect(second.labelLayout?.placement == .adjusted)
    #expect(!drawingProjectionBoundsIntersect(firstBounds, secondBounds))
    #expect(second.labelLayout?.leaderStart2D != nil)
    #expect(second.labelLayout?.leaderEnd2D != nil)
    #expect(result.diagnostics.contains {
        $0.message.contains("adjusted 1 drawing annotation label")
    })
}

@MainActor
@Test func drawingProjectionGeneratesAreaAndPerimeterAnnotationsFromBoundaryAnchors() throws {
    let boundaryAnchors: [MeasurementAnchor] = [
        .worldPoint(Point3D(x: 0.0, y: 0.0, z: 0.0), role: .start),
        .worldPoint(Point3D(x: 2.0, y: 0.0, z: 0.0), role: .point),
        .worldPoint(Point3D(x: 2.0, y: 0.0, z: 3.0), role: .point),
        .worldPoint(Point3D(x: 0.0, y: 0.0, z: 3.0), role: .end),
    ]
    let result = try drawingProjectionResultWithMeasurements([
        MeasurementAnnotation(
            name: "Plate Area",
            kind: .area,
            anchors: boundaryAnchors
        ),
        MeasurementAnnotation(
            name: "Plate Perimeter",
            kind: .perimeter,
            anchors: boundaryAnchors
        ),
    ])

    let areaAnnotation = try #require(result.annotations.first { $0.kind == .area })
    let perimeterAnnotation = try #require(result.annotations.first { $0.kind == .perimeter })

    #expect(result.annotationCount == 2)
    #expect(areaAnnotation.measurementMeters == nil)
    #expect(areaAnnotation.measurementDegrees == nil)
    #expect(abs((areaAnnotation.measurementSquareMeters ?? -1.0) - 6.0) <= 1.0e-12)
    #expect(areaAnnotation.displayText == "Area 6 m^2")
    #expect(areaAnnotation.anchors.count == 4)
    #expect(perimeterAnnotation.measurementSquareMeters == nil)
    #expect(perimeterAnnotation.measurementDegrees == nil)
    #expect(abs((perimeterAnnotation.measurementMeters ?? -1.0) - 10.0) <= 1.0e-12)
    #expect(perimeterAnnotation.displayText == "Perim 10 m")
}

@Test func measurementAnnotationRejectsOpenBoundaryMetrics() {
    let twoPointBoundary: [MeasurementAnchor] = [
        .worldPoint(Point3D(x: 0.0, y: 0.0, z: 0.0), role: .start),
        .worldPoint(Point3D(x: 1.0, y: 0.0, z: 0.0), role: .end),
    ]

    #expect(throws: DocumentValidationError.self) {
        try MeasurementAnnotation(
            name: "Open Perimeter",
            kind: .perimeter,
            anchors: twoPointBoundary
        ).validate()
    }
    #expect(throws: DocumentValidationError.self) {
        try MeasurementAnnotation(
            name: "Open Area",
            kind: .area,
            anchors: twoPointBoundary
        ).validate()
    }
}

@Test func measurementAnnotationRequiresSingleGeneratedTopologyAnchorForTopologyMetrics() throws {
    let sceneNodeID = SceneNodeID()
    let faceAnchor = MeasurementAnchor.topologyReference(
        sceneNodeID: sceneNodeID,
        component: .face(.generatedTopology("face-a")),
        kind: .face,
        persistentName: "face-a"
    )
    let edgeAnchor = MeasurementAnchor.topologyReference(
        sceneNodeID: sceneNodeID,
        component: .edge(.generatedTopology("edge-a")),
        kind: .edge,
        persistentName: "edge-a"
    )
    let worldPoint = MeasurementAnchor.worldPoint(
        Point3D(x: 0.0, y: 0.0, z: 0.0),
        role: .point
    )

    try MeasurementAnnotation(
        name: "Generated Face Area",
        kind: .area,
        anchors: [faceAnchor]
    ).validate()
    try MeasurementAnnotation(
        name: "Generated Edge Length",
        kind: .edgeLength,
        anchors: [edgeAnchor]
    ).validate()

    #expect(throws: DocumentValidationError.self) {
        try MeasurementAnnotation(
            name: "Ambiguous Face Area",
            kind: .area,
            anchors: [faceAnchor, worldPoint]
        ).validate()
    }
    #expect(throws: DocumentValidationError.self) {
        try MeasurementAnnotation(
            name: "Ambiguous Edge Length",
            kind: .edgeLength,
            anchors: [edgeAnchor, worldPoint]
        ).validate()
    }
    #expect(throws: DocumentValidationError.self) {
        try MeasurementAnnotation(
            name: "Wrong Topology Length",
            kind: .edgeLength,
            anchors: [faceAnchor]
        ).validate()
    }
}

@MainActor
@Test func drawingProjectionGeneratesFaceAreaAndEdgeLengthAnnotationsFromGeneratedTopology() throws {
    let session = EditorSession()
    _ = try session.execute(
        .createExtrudedRectangle(
            name: "Metric Box",
            plane: .xy,
            width: .length(2.0, .meter),
            height: .length(3.0, .meter),
            depth: .length(4.0, .meter),
            direction: .normal
        )
    )
    var document = session.document
    try document.setRulerConfiguration(.standard(for: .meter))
    let topology = try TopologySummaryService().summarize(document: document)
    let faceEntry = try #require(topology.entries.first { entry in
        entry.kind == .face
            && abs((entry.areaSquareMeters ?? -1.0) - 6.0) <= 1.0e-9
    })
    let edgeEntry = try #require(topology.entries.first { entry in
        entry.kind == .edge
            && abs((entry.lengthMeters ?? -1.0) - 4.0) <= 1.0e-9
    })
    let faceTarget = try #require(faceEntry.selectionTarget())
    let edgeTarget = try #require(edgeEntry.selectionTarget())
    guard case .face = faceTarget.component,
          case .edge = edgeTarget.component else {
        Issue.record("Generated topology entries must resolve to face and edge selection targets.")
        return
    }

    _ = try document.addMeasurementAnnotation(
        MeasurementAnnotation(
            name: "Selected Face Area",
            kind: .area,
            anchors: [
                .topologyReference(
                    sceneNodeID: faceTarget.sceneNodeID,
                    component: faceTarget.component,
                    kind: .face,
                    persistentName: faceEntry.persistentName,
                    referenceID: faceEntry.referenceID
                ),
            ]
        ),
        objectRegistry: session.objectRegistry
    )
    _ = try document.addMeasurementAnnotation(
        MeasurementAnnotation(
            name: "Selected Edge Length",
            kind: .edgeLength,
            anchors: [
                .topologyReference(
                    sceneNodeID: edgeTarget.sceneNodeID,
                    component: edgeTarget.component,
                    kind: .edge,
                    persistentName: edgeEntry.persistentName,
                    referenceID: edgeEntry.referenceID
                ),
            ]
        ),
        objectRegistry: session.objectRegistry
    )
    let savedView = SavedView(
        name: "Metric Drawing View",
        camera: SavedViewCamera(
            target: .origin,
            distanceMeters: 8.0,
            yawRadians: .pi / 4.0,
            pitchRadians: 0.45
        ),
        projection: .orthographic(heightMeters: 8.0),
        displayScale: SavedViewDisplayScale(ruler: .standard(for: .meter))
    )
    _ = try document.createSavedView(savedView, objectRegistry: session.objectRegistry)

    let result = try DrawingProjectionService().generate(
        document: document,
        query: DrawingProjectionQuery(savedViewID: savedView.id),
        objectRegistry: session.objectRegistry
    )

    let areaAnnotation = try #require(result.annotations.first { $0.kind == .area })
    let edgeAnnotation = try #require(result.annotations.first { $0.kind == .edgeLength })
    #expect(areaAnnotation.anchors.count == 1)
    #expect(abs((areaAnnotation.measurementSquareMeters ?? -1.0) - 6.0) <= 1.0e-9)
    #expect(areaAnnotation.measurementMeters == nil)
    #expect(areaAnnotation.displayText == "Area 6 m^2")
    #expect(edgeAnnotation.anchors.count == 1)
    #expect(abs((edgeAnnotation.measurementMeters ?? -1.0) - 4.0) <= 1.0e-9)
    #expect(edgeAnnotation.measurementSquareMeters == nil)
    #expect(edgeAnnotation.displayText == "Edge 4 m")
}

@MainActor
@Test func drawingProjectionGeneratesBSplineEdgeLengthAnnotationFromGeneratedTopology() throws {
    var document = try drawingProjectionSmoothLoftDocument()
    try document.setRulerConfiguration(.standard(for: .meter))
    let topology = try TopologySummaryService().summarize(document: document)
    let edgeEntry = try #require(topology.entries.first {
        $0.kind == .edge
            && $0.curveKind == "bSpline"
            && ($0.lengthMeters ?? 0.0) > 0.0
    })
    let edgeLength = try #require(edgeEntry.lengthMeters)
    let edgeTarget = try #require(edgeEntry.selectionTarget())
    guard case .edge = edgeTarget.component else {
        Issue.record("Generated B-spline topology entry must resolve to an edge selection target.")
        return
    }
    _ = try document.addMeasurementAnnotation(
        MeasurementAnnotation(
            name: "Selected B-Spline Edge Length",
            kind: .edgeLength,
            anchors: [
                .topologyReference(
                    sceneNodeID: edgeTarget.sceneNodeID,
                    component: edgeTarget.component,
                    kind: .edge,
                    persistentName: edgeEntry.persistentName,
                    referenceID: edgeEntry.referenceID
                ),
            ]
        ),
        objectRegistry: .builtIn
    )
    let savedView = SavedView(
        name: "Smooth Loft Drawing View",
        camera: SavedViewCamera(
            target: Point3D(x: 0.001, y: 0.0, z: 0.005),
            distanceMeters: 0.05,
            yawRadians: .pi / 4.0,
            pitchRadians: 0.45
        ),
        projection: .orthographic(heightMeters: 0.03),
        displayScale: SavedViewDisplayScale(ruler: .standard(for: .meter))
    )
    _ = try document.createSavedView(savedView, objectRegistry: .builtIn)

    let result = try DrawingProjectionService().generate(
        document: document,
        query: DrawingProjectionQuery(savedViewID: savedView.id),
        objectRegistry: .builtIn
    )

    let edgeAnnotation = try #require(result.annotations.first { $0.kind == .edgeLength })
    #expect(abs((edgeAnnotation.measurementMeters ?? -1.0) - edgeLength) <= 1.0e-9)
    #expect(edgeAnnotation.measurementSquareMeters == nil)
    #expect(edgeAnnotation.displayText.hasPrefix("Edge "))
}

@MainActor
@Test func drawingProjectionDiameterAnnotationUsesCenterBoundaryRoles() throws {
    let result = try drawingProjectionResultWithMeasurement(
        name: "Hole Diameter",
        kind: .diameter,
        anchors: [
            .worldPoint(Point3D(x: 0.0, y: 0.0, z: 0.0), role: .center),
            .worldPoint(Point3D(x: 0.75, y: 0.0, z: 0.0), role: .point),
        ]
    )

    let annotation = try #require(result.annotations.first)
    #expect(annotation.measurementMeters == 1.5)
    #expect(annotation.displayText == "Dia 1.5 m")
}

@MainActor
@Test func drawingProjectionDiameterAnnotationUsesEndpointRoles() throws {
    let result = try drawingProjectionResultWithMeasurement(
        name: "Shaft Diameter",
        kind: .diameter,
        anchors: [
            .worldPoint(Point3D(x: -0.75, y: 0.0, z: 0.0), role: .start),
            .worldPoint(Point3D(x: 0.75, y: 0.0, z: 0.0), role: .end),
        ]
    )

    let annotation = try #require(result.annotations.first)
    #expect(annotation.measurementMeters == 1.5)
    #expect(annotation.displayText == "Dia 1.5 m")
}

@MainActor
@Test func drawingProjectionRejectsPerspectiveSavedViewsBeforeProjection() throws {
    let session = EditorSession()
    let savedView = SavedView(
        name: "Perspective View",
        camera: SavedViewCamera(
            target: .origin,
            distanceMeters: 6.0,
            yawRadians: .pi / 4.0,
            pitchRadians: 0.62
        ),
        projection: .perspective(fieldOfViewRadians: .pi / 3.0),
        displayScale: SavedViewDisplayScale(ruler: .standard(for: .meter))
    )
    _ = try session.execute(.createSavedView(savedView))

    #expect(throws: EditorError.self) {
        _ = try DrawingProjectionService().generate(
            document: session.document,
            query: DrawingProjectionQuery(savedViewID: savedView.id),
            objectRegistry: session.objectRegistry,
            currentEvaluation: session.currentEvaluation,
            currentGeneration: session.generation
        )
    }
}

@MainActor
private func drawingProjectionResultWithMeasurement(
    name: String,
    kind: MeasurementAnnotation.Kind,
    anchors: [MeasurementAnchor]
) throws -> DrawingProjectionResult {
    try drawingProjectionResultWithMeasurements([
        MeasurementAnnotation(
            name: name,
            kind: kind,
            anchors: anchors,
            labelPosition: Point3D(x: 0.0, y: 0.25, z: 0.0)
        ),
    ])
}

@MainActor
private func drawingProjectionResultWithMeasurements(
    _ annotations: [MeasurementAnnotation]
) throws -> DrawingProjectionResult {
    let session = EditorSession()
    var document = session.document
    try document.setRulerConfiguration(.standard(for: .meter))
    for annotation in annotations {
        _ = try document.addMeasurementAnnotation(
            annotation,
            objectRegistry: session.objectRegistry
        )
    }
    let savedView = SavedView(
        name: "Annotated Drawing View",
        camera: SavedViewCamera(
            target: .origin,
            distanceMeters: 4.0,
            yawRadians: 0.0,
            pitchRadians: 0.0
        ),
        projection: .orthographic(heightMeters: 4.0),
        displayScale: SavedViewDisplayScale(ruler: .standard(for: .meter))
    )
    _ = try document.createSavedView(savedView, objectRegistry: session.objectRegistry)

    return try DrawingProjectionService().generate(
        document: document,
        query: DrawingProjectionQuery(savedViewID: savedView.id),
        objectRegistry: session.objectRegistry,
        currentEvaluation: session.currentEvaluation,
        currentGeneration: session.generation
    )
}

private func drawingProjectionBoundsIntersect(
    _ first: DrawingProjectionResult.Bounds2D,
    _ second: DrawingProjectionResult.Bounds2D
) -> Bool {
    first.minX < second.maxX
        && first.maxX > second.minX
        && first.minY < second.maxY
        && first.maxY > second.minY
}

private func drawingProjectionBoundsCenter(
    _ bounds: DrawingProjectionResult.Bounds2D
) -> Point2D {
    Point2D(
        x: (bounds.minX + bounds.maxX) * 0.5,
        y: (bounds.minY + bounds.maxY) * 0.5
    )
}

private func drawingProjectionPointApproximatelyEqual(
    _ first: Point2D,
    _ second: Point2D,
    tolerance: Double = 1.0e-12
) -> Bool {
    abs(first.x - second.x) <= tolerance
        && abs(first.y - second.y) <= tolerance
}

private func drawingProjectionSmoothLoftDocument() throws -> DesignDocument {
    var document = DesignDocument.empty()
    let firstProfileID = try drawingProjectionCreateLoftProfile(
        in: &document,
        name: "Drawing Loft Bottom",
        width: 4.0,
        height: 2.0,
        x: 0.0,
        z: 0.0
    )
    let middleProfileID = try drawingProjectionCreateLoftProfile(
        in: &document,
        name: "Drawing Loft Middle",
        width: 5.0,
        height: 2.5,
        x: 3.0,
        z: 5.0
    )
    let lastProfileID = try drawingProjectionCreateLoftProfile(
        in: &document,
        name: "Drawing Loft Top",
        width: 4.0,
        height: 2.0,
        x: 0.0,
        z: 10.0
    )
    _ = try document.createLoft(
        name: "Drawing Smooth Loft",
        sections: [
            LoftSectionReference(profile: ProfileReference(featureID: firstProfileID)),
            LoftSectionReference(profile: ProfileReference(featureID: middleProfileID)),
            LoftSectionReference(profile: ProfileReference(featureID: lastProfileID)),
        ],
        options: LoftOptions(resultKind: .solid, surfaceMode: .smooth)
    )
    return document
}

private func drawingProjectionCreateLoftProfile(
    in document: inout DesignDocument,
    name: String,
    width: Double,
    height: Double,
    x: Double,
    z: Double
) throws -> FeatureID {
    try document.createRectangleSketch(
        name: name,
        plane: drawingProjectionLoftPlane(x: x, z: z),
        width: .length(width, .millimeter),
        height: .length(height, .millimeter)
    )
}

private func drawingProjectionLoftPlane(x: Double, z: Double) -> SketchPlane {
    if x == 0.0 && z == 0.0 {
        return .xy
    }
    return .plane(Plane3D(
        origin: Point3D(x: x / 1000.0, y: 0.0, z: z / 1000.0),
        normal: .unitZ
    ))
}

private func drawingProjectionSketchPoint(
    x: Double,
    y: Double
) -> SketchPoint {
    SketchPoint(
        x: .length(x, .meter),
        y: .length(y, .meter)
    )
}
