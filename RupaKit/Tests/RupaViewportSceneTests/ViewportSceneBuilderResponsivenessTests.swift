import Foundation
import RupaCore
import RupaViewportScene
import SwiftCAD
import Testing

@Test(.timeLimit(.minutes(1)))
func viewportSceneBuilderBuildsRevolvedCircleWithinTheAgentReadBudget() throws {
    var document = DesignDocument.empty()
    let profileID = try document.createCircleSketch(
        name: "Viewport Torus Profile",
        plane: .xy,
        center: SketchPoint(
            x: .length(0.72, .meter),
            y: .length(0.0, .meter)
        ),
        radius: .length(0.04, .meter)
    )
    let revolveID = try document.createRevolve(
        name: "Viewport Torus",
        profile: ProfileReference(featureID: profileID),
        axis: RevolveAxis(origin: .origin, direction: .unitY)
    )

    let start = ContinuousClock.now
    let scene = ViewportSceneBuilder().build(
        document: document,
        ruler: .standard(for: .meter)
    )
    let elapsed = start.duration(to: ContinuousClock.now).components
    let elapsedSeconds = Double(elapsed.seconds) + Double(elapsed.attoseconds) / 1.0e18

    #expect(elapsedSeconds < 15.0)
    #expect(scene.items.contains { $0.featureID == revolveID })
    #expect(scene.items.allSatisfy { item in
        guard case .body(let component) = item.kind else {
            return true
        }
        return component.surfaceKnotDisplays.isEmpty
            && component.surfaceSpanDisplays.isEmpty
    })
}

@Test(.timeLimit(.minutes(1)))
func viewportSceneBuilderReturnsPlacementFailureInsteadOfUnplacedGeometry() throws {
    var document = DesignDocument.empty()
    _ = try document.createExtrudedRectangle(
        name: "Invalid Placement",
        plane: .xy,
        width: .length(1.0, .meter),
        height: .length(1.0, .meter),
        depth: .length(1.0, .meter),
        direction: .normal
    )
    let sceneNodeID = try #require(document.productMetadata.rootSceneNodeIDs.first)
    var matrix = Matrix4x4.identity.values
    matrix[0] = 0.0
    document.productMetadata.sceneNodes[sceneNodeID]?.localTransform = Transform3D(
        matrix: try Matrix4x4(values: matrix)
    )

    let scene = ViewportSceneBuilder().build(
        document: document,
        ruler: .standard(for: .meter)
    )

    #expect(scene.items.isEmpty)
    #expect(scene.failure?.code == .commandInvalid)
}

@Test func placedSketchRetainsAffineCircleAndOutOfPlanePosition() throws {
    var document = DesignDocument.empty()
    let feature = try document.createCircleSketch(name: "Placed Circle", plane: .xy,
        center: SketchPoint(x: .length(0, .meter), y: .length(0, .meter)), radius: .length(1, .meter))
    let node = try #require(document.productMetadata.sceneNodes.values.first { $0.reference == .sketch(feature) })
    let transform = try Transform3D.translation(Vector3D(x: 10, y: 20, z: 30))
        .composed(with: .scale(Vector3D(x: -2, y: 3, z: 4), about: .origin))
    try document.setSceneNodeTransform(id: node.id, localTransform: transform)
    let scene = ViewportSceneBuilder().build(document: document, ruler: .standard(for: .meter))
    #expect(scene.failure == nil)
    let item = try #require(scene.items.first { $0.sceneNodeID == node.id })
    guard case .sketch(let primitives) = item.kind,
          case .circle(_, let center, let radius, _) = try #require(primitives.first) else {
        Issue.record("Expected the source circle primitive.")
        return
    }
    #expect(center == .zero)
    #expect(radius == 1)
    #expect(item.modelTransform.transform == transform)
    #expect(ViewportLayout.transformedPoint(Point3D(x: radius, y: 0, z: 0), by: item.modelTransform)
        == Point3D(x: 8, y: 20, z: 30))
    #expect(ViewportLayout.transformedPoint(Point3D(x: 0, y: 0, z: radius), by: item.modelTransform)
        == Point3D(x: 10, y: 20, z: 34))
}
