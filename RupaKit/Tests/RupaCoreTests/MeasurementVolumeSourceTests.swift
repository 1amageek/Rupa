import Foundation
import SwiftCAD
import Testing
@testable import RupaCore

/// A measurement for bounds only takes a solid's volume from its display mesh and says so; its
/// bounds are the exact measurement's.
@MainActor
@Suite struct MeasurementVolumeSourceTests {
    @Test func aMeshVolumeMeasurementHasTheExactBoundsAndStatesItsMethod() throws {
        let session = EditorSession()
        _ = try session.execute(.createExtrudedRectangle(
            name: "Box", plane: .xy,
            width: .length(0.1, .meter), height: .length(0.1, .meter),
            depth: .length(0.1, .meter), direction: .normal
        ))
        let exact = try MeasurementService().measure(document: session.document, ruler: .standard(for: .meter))
        let mesh = try MeasurementService(volumeSource: .tessellatedMesh).measure(document: session.document, ruler: .standard(for: .meter))
        #expect(exact.bounds == mesh.bounds)
        #expect(exact.solids.map(\.volumeMethod) == [.exactBRep])
        #expect(mesh.solids.map(\.volumeMethod) == [.tessellatedMesh])
        // A box's mesh is exact.
        #expect(abs(mesh.totals.solidVolumeCubicMeters - 0.001) < 1e-12)
    }
}
