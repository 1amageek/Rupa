import RupaCore
import SwiftCAD
import Testing
@testable import RupaUI

@MainActor
@Test(.timeLimit(.minutes(1)))
func canvasPlannerClickGeometryUsesWorkspaceScaleDefaults() throws {
    let session = EditorSession()
    let defaults = WorkspaceScaleDefaults(ruler: session.workspaceState.ruler)
    let planner = canvasCommandPlanner(session: session)

    let plannedRectangle = try planner.clickCommand(
        tool: .sketch,
        targetSceneNodeID: nil,
        modelPoint: Point2D(x: 0.0, y: 0.0),
        modelWorldPoint: nil,
        sketchPlane: .xy,
        placementCellMeters: nil
    )
    guard case let .createRectangleSketchFromCorners(_, rectanglePlane, firstCorner, oppositeCorner) =
        try #require(plannedRectangle)
    else {
        Issue.record("A canvas rectangle click must plan a corner rectangle sketch.")
        return
    }
    let halfWidth = defaults.placedRectangleWidthMeters / 2.0
    let halfHeight = defaults.placedRectangleHeightMeters / 2.0
    #expect(rectanglePlane == .xy)
    #expect(firstCorner == canvasSketchPoint(Point2D(x: -halfWidth, y: -halfHeight)))
    #expect(oppositeCorner == canvasSketchPoint(Point2D(x: halfWidth, y: halfHeight)))

    let circleCenter = Point2D(x: -0.04, y: 0.025)
    let plannedCircle = try planner.clickCommand(
        tool: .circle,
        targetSceneNodeID: nil,
        modelPoint: circleCenter,
        modelWorldPoint: nil,
        sketchPlane: .xy,
        placementCellMeters: nil
    )
    guard case let .createCircleSketch(_, circlePlane, center, radius) = try #require(plannedCircle) else {
        Issue.record("A canvas circle click must plan a circle sketch.")
        return
    }
    #expect(circlePlane == .xy)
    #expect(center == canvasSketchPoint(circleCenter))
    #expect(radius == canvasLength(defaults.curveRadiusMeters))
}

@MainActor
@Test(.timeLimit(.minutes(1)))
func canvasPlannerClickGeometryFollowsRulerWorkspaceScale() throws {
    let scaleCases: [(RulerConfiguration, Double, Double)] = [
        (.standard(for: .meter), 20.0, 12.0),
        (WorkspaceScalePreset.regionalPlanning.rulerConfiguration, 20_000.0, 12_000.0),
    ]

    for (ruler, expectedHalfExtent, expectedRadius) in scaleCases {
        let session = EditorSession()
        _ = try session.execute(.setRulerConfiguration(ruler))
        let planner = canvasCommandPlanner(session: session)

        let plannedRectangle = try planner.clickCommand(
            tool: .sketch,
            targetSceneNodeID: nil,
            modelPoint: Point2D(x: 0.0, y: 0.0),
            modelWorldPoint: nil,
            sketchPlane: .xy,
            placementCellMeters: nil
        )
        guard case let .createRectangleSketchFromCorners(_, _, firstCorner, oppositeCorner) =
            try #require(plannedRectangle)
        else {
            Issue.record("A canvas rectangle click must plan a corner rectangle sketch.")
            return
        }
        #expect(firstCorner == canvasSketchPoint(Point2D(x: -expectedHalfExtent, y: -expectedHalfExtent)))
        #expect(oppositeCorner == canvasSketchPoint(Point2D(x: expectedHalfExtent, y: expectedHalfExtent)))

        let plannedCircle = try planner.clickCommand(
            tool: .circle,
            targetSceneNodeID: nil,
            modelPoint: Point2D(x: 0.0, y: 0.0),
            modelWorldPoint: nil,
            sketchPlane: .xy,
            placementCellMeters: nil
        )
        guard case let .createCircleSketch(_, _, _, radius) = try #require(plannedCircle) else {
            Issue.record("A canvas circle click must plan a circle sketch.")
            return
        }
        #expect(radius == canvasLength(expectedRadius))
    }
}

@MainActor
@Test(.timeLimit(.minutes(1)))
func canvasPlannerSolidClickUsesSuppliedPlacementCell() throws {
    let session = EditorSession()
    let planner = canvasCommandPlanner(session: session)

    let plannedSolid = try planner.clickCommand(
        tool: .solid,
        targetSceneNodeID: nil,
        modelPoint: Point2D(x: 0.0, y: 0.0),
        modelWorldPoint: nil,
        sketchPlane: .xy,
        placementCellMeters: 1.0
    )
    guard case let .createExtrudedRectangleFromCorners(_, plane, firstCorner, oppositeCorner, depth, direction) =
        try #require(plannedSolid)
    else {
        Issue.record("A canvas solid click must plan an extruded corner rectangle.")
        return
    }
    #expect(plane == .xy)
    #expect(firstCorner == canvasSketchPoint(Point2D(x: -0.5, y: -0.5)))
    #expect(oppositeCorner == canvasSketchPoint(Point2D(x: 0.5, y: 0.5)))
    #expect(depth == canvasLength(1.0))
    #expect(direction == .normal)
}

@MainActor
@Test(.timeLimit(.minutes(1)))
func canvasPlannerSolidClickFallsBackToWorkspaceScaleForInvalidCell() throws {
    let session = EditorSession()
    let defaults = WorkspaceScaleDefaults(ruler: session.workspaceState.ruler)
    let planner = canvasCommandPlanner(session: session)
    let invalidCells: [Double?] = [nil, 0.0, -4.0, Double.nan]
    let halfSide = defaults.placedSolidSideMeters / 2.0

    for placementCellMeters in invalidCells {
        let plannedSolid = try planner.clickCommand(
            tool: .solid,
            targetSceneNodeID: nil,
            modelPoint: Point2D(x: 0.0, y: 0.0),
            modelWorldPoint: nil,
            sketchPlane: .xy,
            placementCellMeters: placementCellMeters
        )
        guard case let .createExtrudedRectangleFromCorners(_, _, firstCorner, oppositeCorner, depth, _) =
            try #require(plannedSolid)
        else {
            Issue.record("A canvas solid click must plan an extruded corner rectangle.")
            return
        }
        #expect(firstCorner == canvasSketchPoint(Point2D(x: -halfSide, y: -halfSide)))
        #expect(oppositeCorner == canvasSketchPoint(Point2D(x: halfSide, y: halfSide)))
        #expect(depth == canvasLength(defaults.placedSolidSideMeters))
    }
}

@MainActor
@Test(.timeLimit(.minutes(1)))
func canvasPlannerCurveClicksMatchCanvasSketchCurveDrafts() throws {
    let session = EditorSession()
    let defaults = WorkspaceScaleDefaults(ruler: session.workspaceState.ruler)
    let planner = canvasCommandPlanner(session: session)
    let clickPoint = Point2D(x: -0.04, y: 0.025)

    let plannedArc = try planner.clickCommand(
        tool: .arc,
        targetSceneNodeID: nil,
        modelPoint: clickPoint,
        modelWorldPoint: nil,
        sketchPlane: .xy,
        placementCellMeters: nil
    )
    guard case let .createArcSketch(_, arcPlane, arcCenter, arcRadius, startAngle, endAngle) =
        try #require(plannedArc)
    else {
        Issue.record("A canvas arc click must plan an arc sketch.")
        return
    }
    let arcDraft = try CanvasSketchCurveDrafts.arc(centeredAt: clickPoint, defaults: defaults)
    #expect(arcPlane == .xy)
    #expect(arcCenter == canvasSketchPoint(arcDraft.center))
    #expect(arcRadius == canvasLength(arcDraft.radiusMeters))
    #expect(startAngle == .angle(arcDraft.startAngleRadians, .radian))
    #expect(endAngle == .angle(arcDraft.endAngleRadians, .radian))

    let plannedSpline = try planner.clickCommand(
        tool: .spline,
        targetSceneNodeID: nil,
        modelPoint: clickPoint,
        modelWorldPoint: nil,
        sketchPlane: .xy,
        placementCellMeters: nil
    )
    guard case let .createSplineSketch(_, splinePlane, spline) = try #require(plannedSpline) else {
        Issue.record("A canvas spline click must plan a spline sketch.")
        return
    }
    let splineDraft = try CanvasSketchCurveDrafts.spline(centeredAt: clickPoint, defaults: defaults)
    #expect(splinePlane == .xy)
    #expect(spline.controlPoints == splineDraft.controlPoints.map(canvasSketchPoint))
}

@MainActor
@Test(.timeLimit(.minutes(1)))
func canvasPlannerDragGeometryMatchesCanvasSketchCurveDrafts() throws {
    let session = EditorSession()
    let defaults = WorkspaceScaleDefaults(ruler: session.workspaceState.ruler)
    let planner = canvasCommandPlanner(session: session)

    let plannedRectangle = try planner.dragCommand(
        tool: .sketch,
        startModelPoint: Point2D(x: 0.03, y: 0.04),
        endModelPoint: Point2D(x: -0.01, y: 0.01),
        sketchPlane: .xy,
        startWorldPoint: nil,
        endWorldPoint: nil
    )
    guard case let .createRectangleSketchFromCorners(_, _, firstCorner, oppositeCorner) =
        try #require(plannedRectangle)
    else {
        Issue.record("A canvas rectangle drag must plan a corner rectangle sketch.")
        return
    }
    #expect(firstCorner == canvasSketchPoint(Point2D(x: -0.01, y: 0.01)))
    #expect(oppositeCorner == canvasSketchPoint(Point2D(x: 0.03, y: 0.04)))

    let dragCenter = Point2D(x: 0.01, y: -0.02)
    let dragEdge = Point2D(x: 0.04, y: 0.02)

    let plannedCircle = try planner.dragCommand(
        tool: .circle,
        startModelPoint: dragCenter,
        endModelPoint: dragEdge,
        sketchPlane: .xy,
        startWorldPoint: nil,
        endWorldPoint: nil
    )
    guard case let .createCircleSketch(_, _, circleCenter, circleRadius) = try #require(plannedCircle) else {
        Issue.record("A canvas circle drag must plan a circle sketch.")
        return
    }
    #expect(circleCenter == canvasSketchPoint(dragCenter))
    #expect(circleRadius == canvasLength(0.05))

    let plannedArc = try planner.dragCommand(
        tool: .arc,
        startModelPoint: dragCenter,
        endModelPoint: dragEdge,
        sketchPlane: .xy,
        startWorldPoint: nil,
        endWorldPoint: nil
    )
    guard case let .createArcSketch(_, _, arcCenter, arcRadius, startAngle, endAngle) =
        try #require(plannedArc)
    else {
        Issue.record("A canvas arc drag must plan an arc sketch.")
        return
    }
    let arcDraft = try CanvasSketchCurveDrafts.arc(fromCenter: dragCenter, toRadiusPoint: dragEdge)
    #expect(arcCenter == canvasSketchPoint(arcDraft.center))
    #expect(arcRadius == canvasLength(arcDraft.radiusMeters))
    #expect(startAngle == .angle(arcDraft.startAngleRadians, .radian))
    #expect(endAngle == .angle(arcDraft.endAngleRadians, .radian))

    let splineStart = Point2D(x: 0.0, y: 0.0)
    let splineEnd = Point2D(x: 0.03, y: 0.04)
    let plannedSpline = try planner.dragCommand(
        tool: .spline,
        startModelPoint: splineStart,
        endModelPoint: splineEnd,
        sketchPlane: .xy,
        startWorldPoint: nil,
        endWorldPoint: nil
    )
    guard case let .createSplineSketch(_, _, spline) = try #require(plannedSpline) else {
        Issue.record("A canvas spline drag must plan a spline sketch.")
        return
    }
    let splineDraft = try CanvasSketchCurveDrafts.spline(
        from: splineStart,
        to: splineEnd,
        defaults: defaults
    )
    #expect(spline.controlPoints == splineDraft.controlPoints.map(canvasSketchPoint))

    let plannedSolid = try planner.dragCommand(
        tool: .solid,
        startModelPoint: Point2D(x: 0.02, y: -0.01),
        endModelPoint: Point2D(x: 0.05, y: 0.03),
        sketchPlane: .xy,
        startWorldPoint: nil,
        endWorldPoint: nil
    )
    guard case let .createExtrudedRectangleFromCorners(_, _, _, _, depth, _) = try #require(plannedSolid) else {
        Issue.record("A canvas solid drag must plan an extruded corner rectangle.")
        return
    }
    #expect(depth == canvasLength(defaults.sketchDepthMeters))
}

@MainActor
@Test(.timeLimit(.minutes(1)))
func canvasPlannerAppliesDimensionInputToPlannedGeometry() throws {
    let session = EditorSession()

    let rectangleInput = SketchInputState(
        dimensionInputFocus: .width,
        dimensionInputWidthMeters: 0.06,
        dimensionInputHeightMeters: 0.03
    )
    let plannedRectangle = try canvasCommandPlanner(
        session: session,
        sketchInputState: rectangleInput
    ).clickCommand(
        tool: .sketch,
        targetSceneNodeID: nil,
        modelPoint: Point2D(x: 0.01, y: -0.02),
        modelWorldPoint: nil,
        sketchPlane: .xy,
        placementCellMeters: nil
    )
    guard case let .createRectangleSketchFromCorners(_, _, firstCorner, oppositeCorner) =
        try #require(plannedRectangle)
    else {
        Issue.record("A canvas rectangle click must plan a corner rectangle sketch.")
        return
    }
    #expect(firstCorner == canvasSketchPoint(Point2D(x: -0.02, y: -0.035)))
    #expect(oppositeCorner == canvasSketchPoint(Point2D(x: 0.04, y: -0.005)))

    let lengthInput = SketchInputState(
        dimensionInputFocus: .length,
        dimensionInputLengthMeters: 0.021
    )
    let plannedCircle = try canvasCommandPlanner(
        session: session,
        sketchInputState: lengthInput
    ).dragCommand(
        tool: .circle,
        startModelPoint: Point2D(x: 0.01, y: -0.02),
        endModelPoint: Point2D(x: 0.012, y: -0.02),
        sketchPlane: .xy,
        startWorldPoint: nil,
        endWorldPoint: nil
    )
    guard case let .createCircleSketch(_, _, _, radius) = try #require(plannedCircle) else {
        Issue.record("A canvas circle drag must plan a circle sketch.")
        return
    }
    #expect(radius == canvasLength(0.021))

    let spanAngleRadians = Double.pi / 3.0
    let angleInput = SketchInputState(
        dimensionInputFocus: .angle,
        dimensionInputAngleRadians: spanAngleRadians
    )
    let dragCenter = Point2D(x: 0.01, y: -0.02)
    let dragEdge = Point2D(x: 0.04, y: 0.02)
    let plannedArc = try canvasCommandPlanner(
        session: session,
        sketchInputState: angleInput
    ).dragCommand(
        tool: .arc,
        startModelPoint: dragCenter,
        endModelPoint: dragEdge,
        sketchPlane: .xy,
        startWorldPoint: nil,
        endWorldPoint: nil
    )
    guard case let .createArcSketch(_, _, _, _, startAngle, endAngle) = try #require(plannedArc) else {
        Issue.record("A canvas arc drag must plan an arc sketch.")
        return
    }
    let arcDraft = try CanvasSketchCurveDrafts.arc(
        fromCenter: dragCenter,
        toRadiusPoint: dragEdge,
        spanAngleRadians: CADInputValueNormalizer.standard.angleRadians(spanAngleRadians)
    )
    #expect(startAngle == .angle(arcDraft.startAngleRadians, .radian))
    #expect(endAngle == .angle(arcDraft.endAngleRadians, .radian))
}

@MainActor
@Test(.timeLimit(.minutes(1)))
func canvasPlannerCarriesPolygonToolStateIntoPlannedCommand() throws {
    let session = EditorSession()
    let defaults = WorkspaceScaleDefaults(ruler: session.workspaceState.ruler)
    let polygonState = try PolygonToolState(
        sideCount: 8,
        sizingMode: .inradius,
        inclinationMode: .horizontal
    )
    let clickPoint = Point2D(x: -0.04, y: 0.025)

    let plannedPolygon = try canvasCommandPlanner(
        session: session,
        polygonState: polygonState
    ).clickCommand(
        tool: .polygon,
        targetSceneNodeID: nil,
        modelPoint: clickPoint,
        modelWorldPoint: nil,
        sketchPlane: .xy,
        placementCellMeters: nil
    )
    guard case let .createPolygonSketch(
        _,
        plane,
        center,
        radius,
        sides,
        sizingMode,
        inclinationMode,
        rotationAngle
    ) = try #require(plannedPolygon) else {
        Issue.record("A canvas polygon click must plan a polygon sketch.")
        return
    }
    let draft = try CanvasSketchCurveDrafts.polygon(
        centeredAt: clickPoint,
        sides: polygonState.sideCount,
        sizingMode: polygonState.sizingMode,
        inclinationMode: polygonState.inclinationMode,
        defaults: defaults
    )
    #expect(plane == .xy)
    #expect(sides == 8)
    #expect(sizingMode == .inradius)
    #expect(inclinationMode == .horizontal)
    #expect(center == canvasSketchPoint(draft.center))
    #expect(radius == canvasLength(draft.radiusMeters))
    #expect(rotationAngle == .angle(draft.rotationAngleRadians, .radian))

    let dragEndPoint = Point2D(x: clickPoint.x + 0.002, y: clickPoint.y)
    let radiusInputMeters = 0.018
    let plannedSizedPolygon = try canvasCommandPlanner(
        session: session,
        polygonState: polygonState,
        sketchInputState: SketchInputState(
            dimensionInputFocus: .length,
            dimensionInputLengthMeters: radiusInputMeters
        )
    ).dragCommand(
        tool: .polygon,
        startModelPoint: clickPoint,
        endModelPoint: dragEndPoint,
        sketchPlane: .xy,
        startWorldPoint: nil,
        endWorldPoint: nil
    )
    guard case let .createPolygonSketch(_, _, _, sizedRadius, _, _, _, _) = try #require(
        plannedSizedPolygon
    ) else {
        Issue.record("A canvas polygon drag must plan a polygon sketch.")
        return
    }
    #expect(sizedRadius == canvasLength(radiusInputMeters))

    let rotationInputRadians = Double.pi / 6.0
    let plannedRotatedPolygon = try canvasCommandPlanner(
        session: session,
        polygonState: polygonState,
        sketchInputState: SketchInputState(
            dimensionInputFocus: .angle,
            dimensionInputAngleRadians: rotationInputRadians
        )
    ).dragCommand(
        tool: .polygon,
        startModelPoint: clickPoint,
        endModelPoint: dragEndPoint,
        sketchPlane: .xy,
        startWorldPoint: nil,
        endWorldPoint: nil
    )
    guard case let .createPolygonSketch(_, _, _, _, _, _, _, rotatedAngle) = try #require(
        plannedRotatedPolygon
    ) else {
        Issue.record("A canvas polygon drag must plan a polygon sketch.")
        return
    }
    #expect(rotatedAngle == .angle(
        CADInputValueNormalizer.standard.angleRadians(rotationInputRadians),
        .radian
    ))
}

@MainActor
@Test(.timeLimit(.minutes(1)))
func canvasPlannerRejectsDegenerateRectangleAndCircleDrags() throws {
    let session = EditorSession()
    let planner = canvasCommandPlanner(session: session)

    do {
        _ = try planner.dragCommand(
            tool: .sketch,
            startModelPoint: Point2D(x: 1.0, y: 1.0),
            endModelPoint: Point2D(x: 1.0, y: 2.0),
            sketchPlane: .xy,
            startWorldPoint: nil,
            endWorldPoint: nil
        )
        Issue.record("A zero-width rectangle drag must not plan a command.")
    } catch let error as EditorError {
        #expect(error.code == .commandInvalid)
        #expect(error.message == "Canvas rectangle drag requires a non-zero width and height.")
    }

    do {
        _ = try planner.dragCommand(
            tool: .circle,
            startModelPoint: Point2D(x: 1.0, y: 1.0),
            endModelPoint: Point2D(x: 1.0, y: 1.0),
            sketchPlane: .xy,
            startWorldPoint: nil,
            endWorldPoint: nil
        )
        Issue.record("A zero-radius circle drag must not plan a command.")
    } catch let error as EditorError {
        #expect(error.code == .commandInvalid)
        #expect(error.message == "Canvas circle drag requires a non-zero radius.")
    }
}

@MainActor
@Test(.timeLimit(.minutes(1)))
func canvasPlannerKnifeUsesSnappedFaceWorldPointsForLoop() throws {
    let session = EditorSession()
    _ = try #require(session.createDefaultExtrudedRectangle())
    let topology = try TopologySnapshotService().snapshot(document: session.document)
    let sideFaceEntry = try #require(
        topology.entries.first {
            $0.kind == .face &&
                $0.generatedRole == "sideFace" &&
                abs($0.normal?.z ?? 1.0) < 0.5 &&
                $0.selectionTarget() != nil
        }
    )
    let sideFaceCenter = try #require(sideFaceEntry.center)
    let sideFaceNormal = try #require(sideFaceEntry.normal)
    let sideFaceTarget = try #require(sideFaceEntry.selectionTarget())
    let sideFacePlane = try ConstructionPlaneTargetResolver().plane(
        alignedTo: sideFaceTarget,
        in: session.document,
        objectRegistry: session.objectRegistry
    )
    let coordinateSystem = try SketchPlaneCoordinateSystem(plane: sideFacePlane)
    let centerWorldPoint = Point3D(x: sideFaceCenter.x, y: sideFaceCenter.y, z: sideFaceCenter.z)
    let centerLocalPoint = coordinateSystem.project(centerWorldPoint).point
    let edgeWorldPoint = coordinateSystem.point(
        from: Point2D(x: centerLocalPoint.x + 0.002, y: centerLocalPoint.y)
    )

    #expect(session.selectTarget(sideFaceTarget))

    let polygonState = try PolygonToolState(sideCount: 4, cutsFaces: true)
    let plannedKnife = try canvasCommandPlanner(
        session: session,
        polygonState: polygonState
    ).dragCommand(
        tool: .polygon,
        startModelPoint: Point2D(x: 0.1, y: 0.1),
        endModelPoint: Point2D(x: 0.12, y: 0.1),
        sketchPlane: .xy,
        startWorldPoint: centerWorldPoint,
        endWorldPoint: edgeWorldPoint
    )
    let knifeCommand = try #require(plannedKnife)
    guard case let .createFaceKnife(_, target, loop) = knifeCommand else {
        Issue.record("A polygon knife drag must plan a face knife command.")
        return
    }
    let faceNormal = Vector3D(x: sideFaceNormal.x, y: sideFaceNormal.y, z: sideFaceNormal.z)
    let loopCentroid = loop.reduce(Point3D.origin) { partial, point in
        Point3D(
            x: partial.x + point.x / Double(loop.count),
            y: partial.y + point.y / Double(loop.count),
            z: partial.z + point.z / Double(loop.count)
        )
    }

    #expect(target == sideFaceTarget)
    #expect(loop.count == 4)
    #expect(loop.allSatisfy { abs(($0 - centerWorldPoint).dot(faceNormal)) < 1.0e-10 })
    #expect(abs(loopCentroid.x - centerWorldPoint.x) < 1.0e-10)
    #expect(abs(loopCentroid.y - centerWorldPoint.y) < 1.0e-10)
    #expect(abs(loopCentroid.z - centerWorldPoint.z) < 1.0e-10)
    #expect(loop.contains { abs($0.z - centerWorldPoint.z) > 1.0e-4 })
    #expect(try session.execute(knifeCommand).didMutate)
    #expect(session.evaluationStatus == .valid)
}

@MainActor
func canvasCommandPlanner(
    session: EditorSession,
    polygonState: PolygonToolState? = nil,
    sketchInputState: SketchInputState? = nil
) -> WorkspaceCanvasCommandPlanner {
    WorkspaceCanvasCommandPlanner(
        context: WorkspaceCanvasCommandPlanner.Context(
            document: session.document,
            selection: session.selection,
            workspaceState: session.workspaceState,
            objectRegistry: session.objectRegistry,
            polygonState: polygonState ?? session.polygonToolState,
            sketchInputState: sketchInputState ?? session.sketchInputState
        )
    )
}

private func canvasSketchPoint(_ point: Point2D) -> SketchPoint {
    SketchPoint(x: canvasLength(point.x), y: canvasLength(point.y))
}

private func canvasLength(_ value: Double) -> CADExpression {
    .length(CADInputValueNormalizer.standard.lengthMeters(value), .meter)
}
