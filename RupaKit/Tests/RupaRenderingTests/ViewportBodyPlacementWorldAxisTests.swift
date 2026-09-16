import CoreGraphics
import RupaCore
import RupaViewportScene
import SwiftCAD
import Testing
@testable import RupaRendering

private struct BodyPlacementFixtureError: Error {
    let message: String
}

/// The centre of the body's world box, which is the box the transform gizmo is
/// drawn around and the box its ghost moves while a drag is held.
@MainActor
private func bodyWorldCentre(
    document: DesignDocument,
    ruler: RulerConfiguration,
    sceneNodeID: SceneNodeID
) throws -> (x: Double, y: Double, z: Double) {
    let scene = ViewportSceneBuilder().build(document: document, ruler: ruler)
    guard let item = scene.items.first(where: { item in
        guard case .body = item.kind else { return false }
        return item.sceneNodeID == sceneNodeID
    }) else {
        throw BodyPlacementFixtureError(
            message: "The rebuilt scene has no body for the placed scene node."
        )
    }
    let edit = ViewportObjectEditState(item: item)
    return (
        x: Double(edit.xMin + edit.xMax) / 2.0,
        y: Double(edit.yMin + edit.yMax) / 2.0,
        z: Double(edit.zMin + edit.zMax) / 2.0
    )
}

/// Reads back the whole chain a released transform gizmo commits through, on
/// each world axis in turn: the local frame the shared algebra composes for a
/// world translation, committed as `setSceneNodeTransform`, moves the body's
/// world box along the axis the pressed arrow names and leaves the other two
/// where they were.
///
/// The default body is extruded from a sketch on the `.zx` plane, whose two
/// axes are world Z and world X. A commit that translated that profile sketch
/// instead could reach only those two axes, reached them under each other's
/// names, and could not reach the height axis at all; that is the defect this
/// case is parametrised to catch rather than to describe.
@MainActor
@Test(.timeLimit(.minutes(1)), arguments: ViewportCoordinateAxis.allCases)
func bodyPlacementCommitMovesTheBodyAlongTheWorldAxisTheGizmoNamed(
    axis: ViewportCoordinateAxis
) throws {
    let session = EditorSession()
    guard session.createDefaultExtrudedRectangle() != nil else {
        throw BodyPlacementFixtureError(
            message: "The fixture document did not create the default body."
        )
    }
    let ruler = session.workspaceState.ruler
    let scene = ViewportSceneBuilder().build(document: session.document, ruler: ruler)
    guard let item = scene.items.first(where: { item in
        guard case .body = item.kind else { return false }
        return true
    }), let sceneNodeID = item.sceneNodeID else {
        throw BodyPlacementFixtureError(
            message: "The fixture scene has no body naming a scene node."
        )
    }
    let before = try bodyWorldCentre(
        document: session.document, ruler: ruler, sceneNodeID: sceneNodeID
    )

    let distance = 0.02
    let worldDelta: Vector3D
    switch axis {
    case .x: worldDelta = Vector3D(x: distance, y: 0.0, z: 0.0)
    case .y: worldDelta = Vector3D(x: 0.0, y: distance, z: 0.0)
    case .z: worldDelta = Vector3D(x: 0.0, y: 0.0, z: distance)
    }
    let node = try #require(session.document.productMetadata.sceneNodes[sceneNodeID])
    let parentFrames = try ViewportSceneNodeParentFrames(document: session.document)
    let parentWorldTransform = try #require(
        try parentFrames.parentWorldTransform(of: sceneNodeID)
    )
    let localTransform = try #require(
        try ViewportWorldTransformAlgebra.localTransform(
            applying: try ViewportWorldTransformAlgebra.translation(worldDelta),
            within: parentWorldTransform,
            to: node.localTransform
        )
    )
    session.setSceneNodeTransform(sceneNodeID, localTransform: localTransform)
    #expect(
        session.document.productMetadata.sceneNodes[sceneNodeID]?.localTransform == localTransform
    )

    let after = try bodyWorldCentre(
        document: session.document, ruler: ruler, sceneNodeID: sceneNodeID
    )
    let moved = [
        ViewportCoordinateAxis.x: after.x - before.x,
        ViewportCoordinateAxis.y: after.y - before.y,
        ViewportCoordinateAxis.z: after.z - before.z,
    ]
    let tolerance = 1.0e-9
    for candidate in ViewportCoordinateAxis.allCases {
        let component = try #require(moved[candidate])
        if candidate == axis {
            #expect(abs(component - distance) <= tolerance)
        } else {
            #expect(abs(component) <= tolerance)
        }
    }
}
