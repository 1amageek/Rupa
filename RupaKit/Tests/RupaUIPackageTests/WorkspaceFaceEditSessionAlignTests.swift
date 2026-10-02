import Testing
import RupaCore
import SwiftCAD
@testable import RupaUI

/// Align Surface's dialog aligns several pairs at once, each with its own continuity.
@Suite("Face edit session align")
struct WorkspaceFaceEditSessionAlignTests {
    @Test func everyPairIsItsOwnAlignmentWithItsOwnContinuity() throws {
        let targets = (0..<4).map { _ in SelectionTarget(sceneNodeID: SceneNodeID()) }
        var session = WorkspaceFaceEditSession(kind: .alignSurface(pairs: [
            .init(edge: targets[0], reference: targets[1]), .init(edge: targets[2], reference: targets[3]),
        ]))
        session.continuity = .tangentPlane
        session.pairContinuity[1] = .curvature
        session.boundaryFlow = .normal
        let commands = session.commands()
        #expect(commands.count == 2)
        guard case let .alignSurface(first, firstContinuity, _, _, _, _, _, _, firstFlow) = commands[0],
              case let .alignSurface(second, secondContinuity, _, _, _, _, _, _, _) = commands[1] else {
            Issue.record("Expected two alignments.")
            return
        }
        #expect(first == [targets[0], targets[1]] && second == [targets[2], targets[3]])
        #expect(firstContinuity == .tangentPlane && secondContinuity == .curvature && firstFlow == .normal)
        // Tab steps every pair's continuity together.
        session.stepGrow()
        #expect(session.pairContinuity.isEmpty && session.continuity == .curvature)
    }
}
