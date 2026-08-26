import Testing
import RupaCore
import SwiftCAD
@testable import RupaUI

@MainActor
@Test(.timeLimit(.minutes(1)))
func workspaceCanvasCommandPlannerBuildsExecutableSolidDragWithoutMutatingPlanningState() throws {
    let session = EditorSession()
    let initialGeneration = session.generation
    let plannedCommand = try workspaceCanvasCommandPlanner(session: session).dragCommand(
        tool: .solid,
        startModelPoint: Point2D(x: -0.02, y: -0.01),
        endModelPoint: Point2D(x: 0.02, y: 0.01),
        sketchPlane: .xy,
        startWorldPoint: nil,
        endWorldPoint: nil
    )
    let command = try #require(plannedCommand)

    #expect(session.generation == initialGeneration)
    guard case let .createExtrudedRectangleFromCorners(
        _,
        plane,
        firstCorner,
        oppositeCorner,
        _,
        direction
    ) = command else {
        Issue.record("The solid drag planner must produce an extruded rectangle command.")
        return
    }
    #expect(plane == .xy)
    #expect(firstCorner == SketchPoint(x: .length(-0.02, .meter), y: .length(-0.01, .meter)))
    #expect(oppositeCorner == SketchPoint(x: .length(0.02, .meter), y: .length(0.01, .meter)))
    #expect(direction == .normal)

    let result = try session.execute(command)
    #expect(result.didMutate)
    #expect(session.generation > initialGeneration)
    #expect(session.evaluatedBodyCount == 1)
}

@MainActor
@Test(.timeLimit(.minutes(1)))
func workspaceCanvasCommandPlannerRejectsDegenerateSolidDragBeforeMutation() throws {
    let session = EditorSession()
    let initialGeneration = session.generation

    #expect(throws: EditorError.self) {
        _ = try workspaceCanvasCommandPlanner(session: session).dragCommand(
            tool: .solid,
            startModelPoint: Point2D(x: 0.0, y: 0.0),
            endModelPoint: Point2D(x: 0.0, y: 0.0),
            sketchPlane: .xy,
            startWorldPoint: nil,
            endWorldPoint: nil
        )
    }
    #expect(session.generation == initialGeneration)
    #expect(session.document.cadDocument.designGraph.order.isEmpty)
}

@MainActor
@Test(.timeLimit(.minutes(1)))
func workspaceCanvasCommandPlannerClickRoutesBuildExecutableCommands() throws {
    let session = EditorSession()
    let executableCases: [(ModelingTool, String)] = [
        (.solid, "createExtrudedRectangleFromCorners"),
        (.sketch, "createRectangleSketchFromCorners"),
        (.polygon, "createPolygonSketch"),
        (.arc, "createArcSketch"),
        (.spline, "createSplineSketch"),
        (.surface, "createCircleSketch"),
        (.section, "createSectionPlane"),
    ]

    for (tool, expectedCommandName) in executableCases {
        let plannedCommand = try workspaceCanvasCommandPlanner(session: session).clickCommand(
            tool: tool,
            targetSceneNodeID: nil,
            modelPoint: Point2D(x: 0.01, y: 0.02),
            modelWorldPoint: nil,
            sketchPlane: .xy,
            placementCellMeters: 0.03
        )
        let command = try #require(plannedCommand)
        #expect(command.name == expectedCommandName)
        #expect(try session.execute(command).didMutate)
    }

    for tool in [ModelingTool.select, .measure, .mesh] {
        #expect(try workspaceCanvasCommandPlanner(session: session).clickCommand(
            tool: tool,
            targetSceneNodeID: nil,
            modelPoint: Point2D(x: 0.0, y: 0.0),
            modelWorldPoint: nil,
            sketchPlane: .xy,
            placementCellMeters: nil
        ) == nil)
    }
}

@MainActor
@Test(.timeLimit(.minutes(1)))
func workspaceCanvasCommandPlannerDragRoutesBuildExecutableCommands() throws {
    let session = EditorSession()
    let executableCases: [(ModelingTool, String)] = [
        (.sketch, "createRectangleSketchFromCorners"),
        (.polygon, "createPolygonSketch"),
        (.surface, "createCircleSketch"),
        (.arc, "createArcSketch"),
        (.spline, "createSplineSketch"),
        (.solid, "createExtrudedRectangleFromCorners"),
    ]

    for (tool, expectedCommandName) in executableCases {
        let plannedCommand = try workspaceCanvasCommandPlanner(session: session).dragCommand(
            tool: tool,
            startModelPoint: Point2D(x: -0.01, y: -0.02),
            endModelPoint: Point2D(x: 0.02, y: 0.03),
            sketchPlane: .xy,
            startWorldPoint: nil,
            endWorldPoint: nil
        )
        let command = try #require(plannedCommand)
        #expect(command.name == expectedCommandName)
        #expect(try session.execute(command).didMutate)
    }

    for tool in [ModelingTool.select, .sweep, .mesh, .measure, .section] {
        #expect(try workspaceCanvasCommandPlanner(session: session).dragCommand(
            tool: tool,
            startModelPoint: Point2D(x: 0.0, y: 0.0),
            endModelPoint: Point2D(x: 0.01, y: 0.01),
            sketchPlane: .xy,
            startWorldPoint: nil,
            endWorldPoint: nil
        ) == nil)
    }
}

@MainActor
@Test(.timeLimit(.minutes(1)))
func workspaceCanvasCommandPlannerUsesCurrentSketchSelectionForSolidAndSweep() throws {
    let solidSession = EditorSession()
    _ = try #require(solidSession.createDefaultRectangleSketch())
    let sketchFeatureID = try #require(solidSession.document.cadDocument.designGraph.order.last)
    let sketchNodeID = try #require(solidSession.document.productMetadata.sceneNodes.first { entry in
        entry.value.reference == .sketch(sketchFeatureID)
    }?.key)
    let solidCommand = try workspaceCanvasCommandPlanner(session: solidSession).clickCommand(
        tool: .solid,
        targetSceneNodeID: sketchNodeID,
        modelPoint: Point2D(x: 0.0, y: 0.0),
        modelWorldPoint: nil,
        sketchPlane: .xy,
        placementCellMeters: nil
    )
    #expect(solidCommand?.name == "extrudeProfile")
    #expect(try solidSession.execute(try #require(solidCommand)).didMutate)

    let sweepSession = EditorSession()
    _ = try #require(sweepSession.createDefaultRectangleSketch())
    let profileFeatureID = try #require(sweepSession.document.cadDocument.designGraph.order.last)
    let profileNodeID = try #require(sweepSession.document.productMetadata.sceneNodes.first { entry in
        entry.value.reference == .sketch(profileFeatureID)
    }?.key)
    _ = try sweepSession.execute(
        .createLineSketch(
            name: "Sweep Path",
            plane: .yz,
            start: SketchPoint(x: .length(0.0, .meter), y: .length(0.0, .meter)),
            end: SketchPoint(x: .length(0.0, .meter), y: .length(0.02, .meter))
        )
    )
    let pathFeatureID = try #require(sweepSession.document.cadDocument.designGraph.order.last)
    let pathNodeID = try #require(sweepSession.document.productMetadata.sceneNodes.first { entry in
        entry.value.reference == .sketch(pathFeatureID)
    }?.key)
    _ = sweepSession.selectSceneNode(profileNodeID)
    let sweepCommand = try workspaceCanvasCommandPlanner(session: sweepSession).clickCommand(
        tool: .sweep,
        targetSceneNodeID: pathNodeID,
        modelPoint: Point2D(x: 0.0, y: 0.0),
        modelWorldPoint: nil,
        sketchPlane: .xy,
        placementCellMeters: nil
    )
    #expect(sweepCommand?.name == "createSweep")
    #expect(try sweepSession.execute(try #require(sweepCommand)).didMutate)
}

@MainActor
@Test(.timeLimit(.minutes(1)))
func workspaceCanvasCommandPlannerUsesCurrentGeneratedFaceSelectionForKnife() throws {
    let session = EditorSession()
    _ = try #require(session.createDefaultExtrudedRectangle())
    let bodyFeatureID = try #require(session.document.cadDocument.designGraph.order.last)
    let bodyNodeID = try #require(session.document.productMetadata.sceneNodes.first { entry in
        entry.value.reference == .body(bodyFeatureID)
    }?.key)
    let topology = try TopologySnapshotService().snapshot(document: session.document)
    let faceTarget = try #require(topology.entries.first { entry in
        entry.kind == .face && entry.sceneNodeID == bodyNodeID.description
    }?.selectionTarget())
    #expect(session.selectTarget(faceTarget))
    #expect(session.setPolygonCutsFaces(true))

    let command = try workspaceCanvasCommandPlanner(session: session).dragCommand(
        tool: .polygon,
        startModelPoint: Point2D(x: 0.0, y: 0.0),
        endModelPoint: Point2D(x: 0.005, y: 0.0),
        sketchPlane: .xy,
        startWorldPoint: nil,
        endWorldPoint: nil
    )
    #expect(command?.name == "createFaceKnife")
    #expect(try session.execute(try #require(command)).didMutate)
}

@MainActor
@Test(.timeLimit(.minutes(1)))
func workspaceCanvasCommandPlannerAppliesDimensionInputOnRequestedPlane() throws {
    let session = EditorSession()
    let input = SketchInputState(
        dimensionInputFocus: .width,
        dimensionInputWidthMeters: 0.03,
        dimensionInputHeightMeters: 0.04
    )
    let command = try workspaceCanvasCommandPlanner(
        session: session,
        sketchInputState: input
    ).dragCommand(
        tool: .solid,
        startModelPoint: Point2D(x: 0.0, y: 0.0),
        endModelPoint: Point2D(x: 0.01, y: 0.01),
        sketchPlane: .yz,
        startWorldPoint: nil,
        endWorldPoint: nil
    )

    let requiredCommand = try #require(command)
    guard case let .createExtrudedRectangleFromCorners(
        _,
        plane,
        firstCorner,
        oppositeCorner,
        _,
        _
    ) = requiredCommand else {
        Issue.record("The planner must preserve the requested plane and active dimensions.")
        return
    }
    #expect(plane == .yz)
    #expect(firstCorner == SketchPoint(x: .length(0.0, .meter), y: .length(0.0, .meter)))
    #expect(oppositeCorner == SketchPoint(x: .length(0.03, .meter), y: .length(0.04, .meter)))
}

@MainActor
@Test(.timeLimit(.minutes(1)))
func workspaceCanvasCommandPlannerReportsTypedFailuresForInvalidBranchInputs() throws {
    let session = EditorSession()
    #expect(throws: EditorError.self) {
        _ = try workspaceCanvasCommandPlanner(session: session).clickCommand(
            tool: .sweep,
            targetSceneNodeID: nil,
            modelPoint: Point2D(x: 0.0, y: 0.0),
            modelWorldPoint: nil,
            sketchPlane: .xy,
            placementCellMeters: nil
        )
    }
    let knifeState = try PolygonToolState(sideCount: 4, cutsFaces: true)
    #expect(throws: EditorError.self) {
        _ = try workspaceCanvasCommandPlanner(
            session: session,
            polygonState: knifeState
        ).clickCommand(
            tool: .polygon,
            targetSceneNodeID: nil,
            modelPoint: Point2D(x: 0.0, y: 0.0),
            modelWorldPoint: nil,
            sketchPlane: .xy,
            placementCellMeters: nil
        )
    }
    #expect(throws: EditorError.self) {
        _ = try workspaceCanvasCommandPlanner(session: session).clickCommand(
            tool: .surface,
            targetSceneNodeID: nil,
            modelPoint: Point2D(x: .infinity, y: 0.0),
            modelWorldPoint: nil,
            sketchPlane: .xy,
            placementCellMeters: nil
        )
    }
}

@MainActor
private func workspaceCanvasCommandPlanner(
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
