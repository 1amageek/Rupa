import Foundation
import Testing
import SwiftCAD
@testable import RupaUI
@testable import RupaCore

@Test func constructionPlaneEditBuilderPreservesWorldOriginForStandardPlanes() throws {
    let updated = try WorkspaceConstructionPlaneEditBuilder().planePreservingOrigin(
        from: .xy,
        viewNormal: Vector3D(x: 0.0, y: 4.0, z: 0.0)
    )

    guard case .plane(let plane) = updated else {
        Issue.record("Expected a custom plane after view-based edit.")
        return
    }
    #expect(plane.origin == .origin)
    #expect(abs(plane.normal.x) < 1.0e-12)
    #expect(abs(plane.normal.y - 1.0) < 1.0e-12)
    #expect(abs(plane.normal.z) < 1.0e-12)
}

@Test func constructionPlaneEditBuilderPreservesCustomPlaneOrigin() throws {
    let source = SketchPlane.plane(
        Plane3D(
            origin: Point3D(x: 12.0, y: -4.0, z: 8.0),
            normal: .unitZ
        )
    )

    let updated = try WorkspaceConstructionPlaneEditBuilder().planePreservingOrigin(
        from: source,
        viewNormal: Vector3D(x: 3.0, y: 0.0, z: 0.0)
    )

    guard case .plane(let plane) = updated else {
        Issue.record("Expected a custom plane after view-based edit.")
        return
    }
    #expect(plane.origin == Point3D(x: 12.0, y: -4.0, z: 8.0))
    #expect(abs(plane.normal.x - 1.0) < 1.0e-12)
    #expect(abs(plane.normal.y) < 1.0e-12)
    #expect(abs(plane.normal.z) < 1.0e-12)
}

@Test func constructionPlaneEditBuilderRejectsInvalidViewNormal() throws {
    #expect(throws: EditorError.self) {
        _ = try WorkspaceConstructionPlaneEditBuilder().planePreservingOrigin(
            from: .xy,
            viewNormal: Vector3D(x: 0.0, y: 0.0, z: 0.0)
        )
    }
}

@Test func constructionPlaneEditBuilderMovesStandardPlaneOriginIntoCustomPlane() throws {
    let updated = try WorkspaceConstructionPlaneEditBuilder().planeSettingOriginComponent(
        .y,
        value: 0.25,
        on: .xy
    )

    guard case .plane(let plane) = updated else {
        Issue.record("Expected a moved standard plane to become a custom plane.")
        return
    }
    #expect(plane.origin == Point3D(x: 0.0, y: 0.25, z: 0.0))
    #expect(plane.normal == .unitZ)
}

@Test func constructionPlaneEditBuilderNormalizesEditedNormalComponent() throws {
    let source = SketchPlane.plane(
        Plane3D(
            origin: Point3D(x: 1.0, y: 2.0, z: 3.0),
            normal: .unitY
        )
    )

    let updated = try WorkspaceConstructionPlaneEditBuilder().planeSettingNormalComponent(
        .x,
        value: 1.0,
        on: source
    )

    guard case .plane(let plane) = updated else {
        Issue.record("Expected a custom plane after normal edit.")
        return
    }
    #expect(plane.origin == Point3D(x: 1.0, y: 2.0, z: 3.0))
    #expect(abs(plane.normal.length - 1.0) < 1.0e-12)
    #expect(abs(plane.normal.x - sqrt(0.5)) < 1.0e-12)
    #expect(abs(plane.normal.y - sqrt(0.5)) < 1.0e-12)
    #expect(abs(plane.normal.z) < 1.0e-12)
}

@Test func constructionPlaneEditBuilderRejectsCollapsedEditedNormal() throws {
    let source = SketchPlane.plane(
        Plane3D(
            origin: .origin,
            normal: .unitX
        )
    )

    #expect(throws: (any Error).self) {
        _ = try WorkspaceConstructionPlaneEditBuilder().planeSettingNormalComponent(
            .x,
            value: 0.0,
            on: source
        )
    }
}

@Test func constructionPlaneInspectorStateReportsEditableOriginAndNormal() {
    let id = ConstructionPlaneSourceID()
    let sceneNodeID = SceneNodeID()
    let entry = ConstructionPlaneSummaryResult.Entry(
        id: id,
        name: "Custom Work Plane",
        plane: .plane(Plane3D(
            origin: Point3D(x: 0.1, y: 0.2, z: 0.3),
            normal: .unitX
        )),
        sceneNodeID: sceneNodeID,
        isActive: true
    )

    let state = WorkspaceConstructionPlaneInspectorState(entry: entry)

    #expect(state.id == id)
    #expect(state.name == "Custom Work Plane")
    #expect(state.sceneNodeID == sceneNodeID)
    #expect(state.isActive)
    #expect(state.planeKindTitle == "Custom")
    #expect(state.origin == Point3D(x: 0.1, y: 0.2, z: 0.3))
    #expect(state.normal == .unitX)
}
