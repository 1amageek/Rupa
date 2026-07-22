import RupaCore
import RupaRendering
import SwiftCAD
import Testing
@testable import RupaUI

@MainActor
@Test func constructionPlaneViewportOriginDragEditCommitsThroughSession() throws {
    let session = WorkspaceLaunchSessionFactory.makeSession(
        arguments: [
            WorkspaceLaunchSessionFactory.selectedCustomConstructionPlaneFixtureArgument,
        ]
    )
    let entry = try #require(
        ConstructionPlaneSummaryService().summarize(
            document: session.document,
            activePlaneID: session.workspaceState.activeConstructionPlaneID
        ).planes.first
    )
    let sceneNodeID = try #require(entry.sceneNodeID)
    let targetOrigin = Point3D(x: 0.48, y: -0.10, z: 0.22)
    let dragTarget = ViewportConstructionPlaneDragTarget(
        constructionPlaneID: entry.id,
        sceneNodeID: sceneNodeID,
        handle: .origin,
        origin: targetOrigin,
        normal: Vector3D(x: 0.0, y: 1.0, z: 0.0)
    )

    let edit = try #require(
        try WorkspaceConstructionPlaneViewportDragCommitService(
            editBuilder: WorkspaceConstructionPlaneEditBuilder(
                tolerance: session.document.modelingSettings.tolerance
            )
        ).edit(
            for: dragTarget,
            entries: [entry]
        )
    )
    let result = session.setConstructionPlane(id: edit.entry.id, plane: edit.plane)

    #expect(result != nil)
    #expect(edit.successMessage == "Updated construction plane Arbitrary CPlane origin.")
    guard case .plane(let updatedPlane) = session.activeConstructionPlane?.plane else {
        Issue.record("Expected the active plane to stay selected and custom after drag commit.")
        return
    }
    #expect(updatedPlane.origin == targetOrigin)
    #expect(abs(updatedPlane.normal.length - 1.0) < 1.0e-12)
    #expect(session.selection.selectedTargets.count == 1)
    #expect(session.selection.selectedTargets.first?.component == .constructionPlane(entry.id))
}

@MainActor
@Test func constructionPlaneViewportNormalDragEditCommitsThroughSession() throws {
    let session = WorkspaceLaunchSessionFactory.makeSession(
        arguments: [
            WorkspaceLaunchSessionFactory.selectedCustomConstructionPlaneFixtureArgument,
        ]
    )
    let entry = try #require(
        ConstructionPlaneSummaryService().summarize(
            document: session.document,
            activePlaneID: session.workspaceState.activeConstructionPlaneID
        ).planes.first
    )
    let sceneNodeID = try #require(entry.sceneNodeID)
    let targetNormal = Vector3D(x: -0.2, y: 0.8, z: 0.4)
    let normalizedTargetNormal = try targetNormal.normalized(tolerance: 1.0e-12)
    let sourcePlane = try #require(entry.plane.customPlane)
    let dragTarget = ViewportConstructionPlaneDragTarget(
        constructionPlaneID: entry.id,
        sceneNodeID: sceneNodeID,
        handle: .normal,
        origin: .origin,
        normal: targetNormal
    )

    let edit = try #require(
        try WorkspaceConstructionPlaneViewportDragCommitService(
            editBuilder: WorkspaceConstructionPlaneEditBuilder(
                tolerance: session.document.modelingSettings.tolerance
            )
        ).edit(
            for: dragTarget,
            entries: [entry]
        )
    )
    let result = session.setConstructionPlane(id: edit.entry.id, plane: edit.plane)

    #expect(result != nil)
    #expect(edit.successMessage == "Updated construction plane Arbitrary CPlane normal.")
    guard case .plane(let updatedPlane) = session.activeConstructionPlane?.plane else {
        Issue.record("Expected the active plane to stay selected and custom after drag commit.")
        return
    }
    #expect(updatedPlane.origin == sourcePlane.origin)
    #expect(abs(updatedPlane.normal.length - 1.0) < 1.0e-12)
    #expect(abs(updatedPlane.normal.x - normalizedTargetNormal.x) < 1.0e-12)
    #expect(abs(updatedPlane.normal.y - normalizedTargetNormal.y) < 1.0e-12)
    #expect(abs(updatedPlane.normal.z - normalizedTargetNormal.z) < 1.0e-12)
}

@MainActor
@Test func constructionPlaneViewportDragEditIgnoresMismatchedPlaneTarget() throws {
    let session = WorkspaceLaunchSessionFactory.makeSession(
        arguments: [
            WorkspaceLaunchSessionFactory.selectedCustomConstructionPlaneFixtureArgument,
        ]
    )
    let entry = try #require(
        ConstructionPlaneSummaryService().summarize(
            document: session.document,
            activePlaneID: session.workspaceState.activeConstructionPlaneID
        ).planes.first
    )
    let dragTarget = ViewportConstructionPlaneDragTarget(
        constructionPlaneID: ConstructionPlaneSourceID(),
        sceneNodeID: SceneNodeID(),
        handle: .origin,
        origin: .origin,
        normal: .unitZ
    )

    let edit = try WorkspaceConstructionPlaneViewportDragCommitService(
        editBuilder: WorkspaceConstructionPlaneEditBuilder(
            tolerance: session.document.modelingSettings.tolerance
        )
    ).edit(
        for: dragTarget,
        entries: [entry]
    )

    #expect(edit == nil)
}

private extension SketchPlane {
    var customPlane: Plane3D? {
        guard case .plane(let plane) = self else {
            return nil
        }
        return plane
    }
}
