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
