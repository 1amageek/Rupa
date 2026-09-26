import RupaCore
import Testing
@testable import RupaUI

/// Place picks its source once and then places at every destination with the session's options.
@Suite struct WorkspacePlaceSessionTests {
    @Test func placementsWaitForTheSourceAndRepeatForConsecutiveCopies() throws {
        let box = SceneNodeID()
        var session = WorkspacePlaceSession(rootSceneNodeIDs: [box])
        let destination = WorkspacePlaceSession.Reference(point: Point3D(x: 1, y: 0, z: 0), normal: nil)
        #expect(throws: EditorError.self) {
            _ = try session.command(destination: destination)
        }

        session.pickSource(WorkspacePlaceSession.Reference(point: .origin, normal: nil))
        session.copyCount = 3
        session.output = .componentInstance
        guard case .placeSceneNodes(let ids, let placements, let output) = try session.command(destination: destination) else {
            Issue.record("Place must submit placeSceneNodes.")
            return
        }
        #expect(ids == [box])
        #expect(output == .componentInstance)
        #expect(placements.count == 3)
        for (index, placement) in placements.enumerated() {
            #expect(abs(placement.matrix.values[3] - Double(index + 1)) < 1.0e-12)
        }
    }
}
