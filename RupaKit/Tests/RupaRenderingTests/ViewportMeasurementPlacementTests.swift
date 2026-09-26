import RupaCore
import SwiftCAD
import Testing
@testable import RupaRendering

/// Measure places the dimension along an axis before it is confirmed, and right-click confirms the
/// straight distance.
@Suite struct ViewportMeasurementPlacementTests {
    private func endpoint(_ x: Double, _ y: Double) -> ViewportMeasurementEndpoint {
        ViewportMeasurementEndpoint(point: Point3D(x: x, y: y, z: 0), source: .constructionPlane(.xy))
    }

    @Test func twoPointsThenPlacementThenClickConfirmsTheAxisDimension() throws {
        var session = ViewportMeasurementSession()
        session.click(endpoint(0, 0))
        session.click(endpoint(3, 4))
        #expect(session.state.phase == .placing)
        #expect(!session.state.canSave)
        session.place(cursor: Point3D(x: 1, y: -2, z: 0), axis: .unitX)
        #expect(session.state.distanceMeters == 3)
        session.click(nil)
        #expect(session.state.phase == .completed)
        #expect(session.state.canSave)
        let annotation = try session.state.annotation(named: "Distance 1", in: SceneNodeHierarchy(metadata: DesignDocument.empty().productMetadata))
        #expect(annotation.placementAxis == .unitX)
        #expect(annotation.labelPosition == Point3D(x: 1, y: -2, z: 0))
        #expect(try session.state.dimension()?.dimensionStart == Point3D(x: 0, y: -2, z: 0))
    }

    @Test func rightClickWhilePlacingConfirmsTheStraightDistance() {
        var session = ViewportMeasurementSession()
        session.click(endpoint(0, 0))
        session.click(endpoint(3, 4))
        session.place(cursor: Point3D(x: 1, y: -2, z: 0), axis: .unitX)
        session.confirmStraight()
        #expect(session.state.phase == .completed)
        #expect(session.state.placementAxis == nil)
        #expect(session.state.distanceMeters == 5)
    }

    @Test func aSeededEdgeStartsPlacingWithItsAnchors() throws {
        var session = ViewportMeasurementSession()
        let anchor = MeasurementAnchor.worldPoint(Point3D(x: 0, y: 0, z: 0))
        session.measure(
            from: ViewportMeasurementEndpoint(point: .origin, source: .anchor(anchor)),
            to: ViewportMeasurementEndpoint(point: Point3D(x: 0, y: 2, z: 0), source: .anchor(anchor))
        )
        #expect(session.state.phase == .placing)
        session.click(nil)
        let anchors = try session.state.savedAnchors(in: SceneNodeHierarchy(metadata: DesignDocument.empty().productMetadata))
        #expect(anchors.map(\.role) == [.start, .end])
    }
}
