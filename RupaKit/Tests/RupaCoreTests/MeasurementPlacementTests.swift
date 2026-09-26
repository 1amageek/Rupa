import Foundation
import SwiftCAD
import Testing
@testable import RupaCore

/// Measure Distance dimensions are placed along construction-plane axes, follow the geometry they
/// were snapped to and are listed under Measurements.
@Suite struct MeasurementPlacementTests {
    private let start = Point3D(x: 0, y: 0, z: 0)
    private let end = Point3D(x: 3, y: 4, z: 0)

    @Test func axisAndStraightDimensionsGiveTheirValuesAndLines() throws {
        let alongX = try MeasurementDimensionGeometry(start: start, end: end, axis: .unitX, labelPosition: Point3D(x: 1, y: -2, z: 0))
        #expect(alongX.valueMeters == 3)
        #expect(alongX.dimensionStart == Point3D(x: 0, y: -2, z: 0))
        #expect(alongX.dimensionEnd == Point3D(x: 3, y: -2, z: 0))
        #expect(alongX.labelAnchor == Point3D(x: 1.5, y: -2, z: 0))
        #expect(alongX.extensionLines.count == 2)

        let straight = try MeasurementDimensionGeometry(start: start, end: end, axis: nil, labelPosition: nil)
        #expect(straight.valueMeters == 5)
        #expect(straight.dimensionStart == start && straight.dimensionEnd == end)
        #expect(straight.extensionLines.isEmpty)
        #expect(throws: EditorError.self) { _ = try MeasurementDimensionGeometry(start: start, end: start, axis: nil, labelPosition: nil) }
    }

    @Test func theCursorChoosesTheAxisMostPerpendicularOnScreenToItsOffset() {
        let axes = [Vector3D.unitX, .unitY, .unitZ]
        let midpoint = Point3D(x: 1.5, y: 2, z: 0)
        // Looking down Z: dragging the dimension down measures along X, sideways along Y.
        let below = MeasurementDimensionGeometry.placementAxis(
            start: start, end: end, cursor: midpoint + Vector3D(x: 0, y: -3, z: 0), viewNormal: .unitZ, planeAxes: axes
        )
        #expect(below == .unitX)
        let beside = MeasurementDimensionGeometry.placementAxis(
            start: start, end: end, cursor: midpoint + Vector3D(x: 3, y: 0, z: 0), viewNormal: .unitZ, planeAxes: axes
        )
        #expect(beside == .unitY)
        // Points that differ only along the view direction have no axis to measure on screen.
        #expect(MeasurementDimensionGeometry.placementAxis(
            start: start, end: Point3D(x: 0, y: 0, z: 2), cursor: Point3D(x: 1, y: 0, z: 1), viewNormal: .unitZ, planeAxes: axes
        ) == nil)
    }

    @Test func snappedEdgeEndsFollowTheEdgeWhenTheBodyChanges() throws {
        var document = DesignDocument.empty()
        let featureID = try document.createExtrudedRectangle(
            name: "Box", plane: .xy, width: .length(0.1, .meter), height: .length(0.1, .meter),
            depth: .length(0.1, .meter), direction: .normal
        )
        let topology = try TopologySnapshotService().snapshot(document: document, metricPolicy: .omit)
        // An edge of the top face: both of its ends lie at the extrude depth.
        let entry = try #require(topology.entries.first {
            $0.kind == .edge && ($0.start.map { abs($0.z) > 0.05 } ?? false) && ($0.end.map { abs($0.z) > 0.05 } ?? false)
        })
        let target = try #require(entry.selectionTarget())
        let candidate = SnapCandidate(
            kind: .edgeEnd, point: Point2D(x: 0, y: 0), distanceMeters: 0, label: "End",
            topologySource: SnapTopologyReference(
                sceneNodeID: target.sceneNodeID, component: target.component, kind: .edge,
                persistentName: entry.subshapeID, referenceID: entry.referenceID, worldPoint: entry.end
            )
        )
        let anchor = try #require(MeasurementAnchor.associative(for: candidate, role: .end))
        #expect(anchor.kind == .topologyEdgeParameter)
        let before = try #require(try MeasurementAnchorWorldPointResolver().resolvedAnchor(anchor, in: document, topology: topology))
        #expect(abs(before.worldPoint.z - 0.1) < 1e-9)

        try document.setExtrudeDistance(featureID: featureID, distance: .length(0.2, .meter))
        let changed = try TopologySnapshotService().snapshot(document: document, metricPolicy: .omit)
        let after = try #require(try MeasurementAnchorWorldPointResolver().resolvedAnchor(anchor, in: document, topology: changed))
        #expect(abs(after.worldPoint.z - 0.2) < 1e-9)

        let points = try #require(try document.measuredCurvePoints(for: target, topology: changed))
        #expect(abs((points.end.worldPoint - points.start.worldPoint).length - (try #require(entry.start).distance(to: try #require(entry.end)))) < 1e-9)
    }

    @Test func savedMeasurementsGoIntoOneMeasurementsGroup() throws {
        var document = DesignDocument.empty()
        for index in 0..<2 {
            try document.addMeasurementAnnotation(MeasurementAnnotation(
                name: "Distance \(index + 1)", kind: .distance,
                anchors: [.worldPoint(start, role: .start), .worldPoint(end, role: .end)],
                labelPosition: Point3D(x: 1, y: -1, z: 0), placementAxis: .unitX
            ))
        }
        let root = try #require(document.productMetadata.rootSceneNodeIDs.first)
        let groups = document.productMetadata.sceneNodes[root]?.childIDs.compactMap { document.productMetadata.sceneNodes[$0] }
            .filter { $0.name == DesignDocument.measurementsGroupName } ?? []
        #expect(groups.count == 1)
        #expect(groups.first?.childIDs.count == 2)
    }
}

private extension TopologySummaryResult.Entry.Point {
    func distance(to other: Self) -> Double {
        ((other.x - x) * (other.x - x) + (other.y - y) * (other.y - y) + (other.z - z) * (other.z - z)).squareRoot()
    }
}
