import Foundation
import SwiftCAD
import Testing
@testable import RupaCore

/// Topology snapshot face areas and centers come from Swift-CAD's exact face measurement.
@Suite struct TopologyFaceMeasurementTests {
    @Test func cylinderFacesReportExactAreasAndCentroids() throws {
        var document = DesignDocument.empty()
        _ = try document.createExtrudedCircle(
            name: "Cylinder", plane: .xy, center: SketchPoint(x: .length(0, .meter), y: .length(0, .meter)),
            radius: .length(0.02, .meter), depth: .length(0.05, .meter), direction: .normal
        )
        let faces = try TopologySnapshotService().snapshot(document: document).entries.filter { $0.kind == .face }
        let sides = faces.filter { $0.surfaceKind == "cylinder" }
        let caps = faces.filter { $0.surfaceKind == "plane" }
        #expect(!sides.isEmpty)
        #expect(caps.count == 2)

        var sideArea = 0.0
        var moment = (x: 0.0, y: 0.0, z: 0.0)
        for side in sides {
            let area = try #require(side.areaSquareMeters)
            let center = try #require(side.center)
            sideArea += area
            moment = (moment.x + center.x * area, moment.y + center.y * area, moment.z + center.z * area)
        }
        #expect(abs(sideArea - 2 * .pi * 0.02 * 0.05) < 1e-14)
        // Together the side faces center on the axis halfway up.
        #expect(abs(moment.x / sideArea) < 1e-12)
        #expect(abs(moment.y / sideArea) < 1e-12)
        #expect(abs(moment.z / sideArea - 0.025) < 1e-12)

        for cap in caps {
            #expect(abs((cap.areaSquareMeters ?? -1) - .pi * 0.02 * 0.02) < 1e-14)
            let center = try #require(cap.center)
            #expect(abs(center.x) < 1e-12 && abs(center.y) < 1e-12)
        }
    }
}
