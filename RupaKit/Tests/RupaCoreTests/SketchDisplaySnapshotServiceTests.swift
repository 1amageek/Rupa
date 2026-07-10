import SwiftCAD
import Testing
@testable import RupaCore

@Test func sketchDisplaySnapshotServiceReportsRectanglePrimitivesBoundsAndRegions() throws {
    var document = DesignDocument.empty()
    let featureID = try document.createRectangleSketch(
        name: "Snapshot Rectangle",
        plane: .xy,
        width: .length(4.0, .millimeter),
        height: .length(2.0, .millimeter)
    )

    let snapshots = SketchDisplaySnapshotService().snapshots(
        document: document,
        ruler: .standard(for: .millimeter)
    )
    let snapshot = try #require(snapshots[featureID])

    #expect(snapshot.featureID == featureID)
    #expect(snapshot.plane == .xy)
    #expect(abs(snapshot.bounds.width - 0.004) <= 1.0e-12)
    #expect(abs(snapshot.bounds.height - 0.002) <= 1.0e-12)
    #expect(snapshot.primitives.count == 4)
    #expect(snapshot.regions.count == 1)
    #expect(snapshot.singleCircleProfileRadiusMeters == nil)
    #expect(snapshot.straightOpenPathVector == nil)
}

@Test func sketchDisplaySnapshotServiceReportsCircleProfileRadiusAndRegion() throws {
    var document = DesignDocument.empty()
    let featureID = try document.createCircleSketch(
        name: "Snapshot Circle",
        plane: .xy,
        center: SketchPoint(
            x: .length(1.0, .millimeter),
            y: .length(2.0, .millimeter)
        ),
        radius: .length(5.0, .millimeter)
    )

    let snapshots = SketchDisplaySnapshotService().snapshots(
        document: document,
        ruler: .standard(for: .millimeter)
    )
    let snapshot = try #require(snapshots[featureID])

    #expect(abs(snapshot.bounds.width - 0.010) <= 1.0e-12)
    #expect(abs(snapshot.bounds.height - 0.010) <= 1.0e-12)
    #expect(snapshot.primitives.count == 1)
    #expect(snapshot.regions.count == 1)
    #expect(abs((snapshot.singleCircleProfileRadiusMeters ?? 0.0) - 0.005) <= 1.0e-12)
    guard case .circle(_, let center, let radiusMeters) = try #require(snapshot.primitives.first) else {
        Issue.record("Expected a circle primitive.")
        return
    }
    #expect(abs(center.x - 0.001) <= 1.0e-12)
    #expect(abs(center.y - 0.002) <= 1.0e-12)
    #expect(abs(radiusMeters - 0.005) <= 1.0e-12)
}

@Test func sketchDisplaySnapshotServiceReportsStraightOpenPathVector() throws {
    var document = DesignDocument.empty()
    let featureID = try document.createLineSketch(
        name: "Snapshot Path",
        plane: .yz,
        start: SketchPoint(
            x: .length(0.0, .millimeter),
            y: .length(0.0, .millimeter)
        ),
        end: SketchPoint(
            x: .length(0.0, .millimeter),
            y: .length(20.0, .millimeter)
        )
    )

    let snapshots = SketchDisplaySnapshotService().snapshots(
        document: document,
        ruler: .standard(for: .millimeter)
    )
    let snapshot = try #require(snapshots[featureID])
    let vector = try #require(snapshot.straightOpenPathVector)

    #expect(abs(vector.x) <= 1.0e-12)
    #expect(abs(vector.y) <= 1.0e-12)
    #expect(abs(vector.z - 0.020) <= 1.0e-12)
}

@Test func designDisplaySnapshotServiceReportsExtrudesAndStraightPrismSweeps() throws {
    var document = DesignDocument.empty()
    let extrudeProfileID = try document.createRectangleSketch(
        name: "Extrude Snapshot Profile",
        plane: .xy,
        width: .length(4.0, .millimeter),
        height: .length(2.0, .millimeter)
    )
    let extrudeID = try document.extrudeProfile(
        name: "Extrude Snapshot Body",
        profile: ProfileReference(featureID: extrudeProfileID),
        distance: .length(12.0, .millimeter),
        direction: .normal
    )
    let sweepProfileID = try document.createRectangleSketch(
        name: "Sweep Snapshot Profile",
        plane: .xy,
        width: .length(3.0, .millimeter),
        height: .length(1.0, .millimeter)
    )
    let sweepPathID = try document.createLineSketch(
        name: "Sweep Snapshot Path",
        plane: .yz,
        start: SketchPoint(
            x: .length(0.0, .millimeter),
            y: .length(0.0, .millimeter)
        ),
        end: SketchPoint(
            x: .length(0.0, .millimeter),
            y: .length(20.0, .millimeter)
        )
    )
    let sweepID = try document.createSweep(
        name: "Sweep Snapshot Body",
        sections: [.profile(ProfileReference(featureID: sweepProfileID))],
        path: SweepPathReference(featureID: sweepPathID),
        options: SweepOptions(
            distanceFraction: .constant(.scalar(0.5))
        )
    )

    let snapshot = DesignDisplaySnapshotService().snapshot(
        document: document,
        ruler: .standard(for: .millimeter)
    )
    let extrude = try #require(snapshot.extrudes[extrudeID])
    let sweep = try #require(snapshot.straightPrismSweeps[sweepID])

    #expect(snapshot.bodies.isEmpty)
    #expect(extrude.profileFeatureID == extrudeProfileID)
    #expect(abs(extrude.depthMeters - 0.012) <= 1.0e-12)
    #expect(sweep.profileFeatureID == sweepProfileID)
    #expect(sweep.pathFeatureID == sweepPathID)
    #expect(abs(sweep.depthMeters - 0.010) <= 1.0e-12)
    guard case .vector(let direction) = sweep.direction else {
        Issue.record("Expected a vector direction for the straight prism sweep.")
        return
    }
    #expect(abs(direction.x) <= 1.0e-12)
    #expect(abs(direction.y) <= 1.0e-12)
    #expect(abs(direction.z - 1.0) <= 1.0e-12)
}

@MainActor
@Test func designDisplaySnapshotResultIncludesEvaluatedBodyTopologyForAgents() throws {
    let session = EditorSession()
    _ = try #require(session.createDefaultExtrudedRectangle())

    let result = try DesignDisplaySnapshotService().result(
        document: session.document,
        workspaceState: session.workspaceState,
        generation: session.generation,
        dirty: session.isDirty
    )
    let body = try #require(result.bodies.first)

    #expect(result.generation == session.generation)
    #expect(result.dirty == session.isDirty)
    #expect(result.sketches.count == 1)
    #expect(result.extrudes.count == 1)
    #expect(result.bodies.count == 1)
    #expect(body.mesh.positions.isEmpty == false)
    #expect(body.mesh.indices.count >= 3)
    #expect(body.topology.faces.count == 6)
    #expect(body.topology.edges.count == 12)
    #expect(body.topology.vertices.count == 8)
}
