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

    @Test func theDialogOpensOnPlasticitysDefaults() throws {
        // G0, Tension 0.50 (the kernel's neutral scale 1), influence 0, Boundary Adjacent.
        let targets = (0..<2).map { _ in SelectionTarget(sceneNodeID: SceneNodeID()) }
        var session = WorkspaceFaceEditSession(kind: .alignSurface(pairs: [.init(edge: targets[0], reference: targets[1])]))
        #expect(session.continuity == .positional && session.tension == 0.5)
        #expect(session.inputShapeInfluence == 0 && session.boundaryFlow == .adjacent)
        guard case let .alignSurface(_, _, neutral, _, _, _, _, _, _) = session.commands()[0] else {
            Issue.record("Expected an alignment.")
            return
        }
        #expect(neutral == 1)
        // The shown tension is 4^(t − 0.5) on the kernel's scale: 0 halves it, 1 doubles it.
        session.tension = 0
        guard case let .alignSurface(_, _, flat, _, _, _, _, _, _) = session.commands()[0] else { return }
        session.tension = 1
        guard case let .alignSurface(_, _, full, _, _, _, _, _, _) = session.commands()[0] else { return }
        #expect(flat == 0.5 && full == 2)
    }

    @Test func everyPairTakesItsOwnTension() throws {
        let targets = (0..<4).map { _ in SelectionTarget(sceneNodeID: SceneNodeID()) }
        var session = WorkspaceFaceEditSession(kind: .alignSurface(pairs: [
            .init(edge: targets[0], reference: targets[1]), .init(edge: targets[2], reference: targets[3]),
        ]))
        session.continuity = .tangentPlane
        session.pairTension[1] = 1
        let commands = session.commands()
        guard case let .alignSurface(_, _, first, _, _, _, _, _, _) = commands[0],
              case let .alignSurface(_, _, second, _, _, _, _, _, _) = commands[1] else {
            Issue.record("Expected two alignments.")
            return
        }
        #expect(first == 1 && second == 2)
    }
}
