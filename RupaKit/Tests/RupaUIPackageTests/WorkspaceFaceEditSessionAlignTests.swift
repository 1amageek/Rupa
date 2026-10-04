import Foundation
import Testing
import RupaCore
import SwiftCAD
@testable import RupaUI

/// Align Surface's dialog aligns several pairs at once, each with its own continuity.
@Suite("Face edit session align")
struct WorkspaceFaceEditSessionAlignTests {
    /// Each aligned edge carries a badge with its pair's continuity; a click steps that pair alone.
    @Test func aBadgeClickStepsItsPairsContinuity() {
        let targets = (0..<4).map { _ in SelectionTarget(sceneNodeID: SceneNodeID()) }
        var session = WorkspaceFaceEditSession(kind: .alignSurface(pairs: [
            .init(edge: targets[0], reference: targets[1]), .init(edge: targets[2], reference: targets[3]),
        ]))
        #expect(session.continuityBadges.map(\.target) == [targets[0], targets[2]])
        #expect(session.continuityBadges.map(\.label) == ["G0", "G0"])
        let firstStep = session.stepContinuity(of: targets[2])
        let secondStep = session.stepContinuity(of: targets[2])
        #expect(firstStep && secondStep)
        #expect(session.continuityBadges.map(\.label) == ["G0", "G2"])
        #expect(session.pairContinuity[1] == .curvature && session.pairContinuity[0] == nil)
        let referenceStepped = session.stepContinuity(of: targets[1])
        #expect(referenceStepped == false)
    }

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
        guard case let .alignSurface(first, firstContinuity, _, _, _, _, _, _, firstFlow, firstKeeps) = commands[0],
              case let .alignSurface(second, secondContinuity, _, _, _, _, _, _, _, secondKeeps) = commands[1] else {
            Issue.record("Expected two alignments.")
            return
        }
        #expect(first == [targets[0], targets[1]] && second == [targets[2], targets[3]])
        #expect(firstContinuity == .tangentPlane && secondContinuity == .curvature && firstFlow == .normal)
        // Edges of two sheets: neither keeps another's.
        #expect(firstKeeps == false && secondKeeps == false)
        // Tab steps every pair's continuity together.
        session.stepGrow()
        #expect(session.pairContinuity.isEmpty && session.continuity == .curvature)
    }

    /// Two edges of one sheet in one dialog (Plasticity's align-3): the second keeps the first, and
    /// takes no refit that would undo it.
    @Test func aSheetsSecondEdgeKeepsItsFirst() {
        let sheet = SceneNodeID()
        let edges = (0..<2).map { _ in SelectionTarget(sceneNodeID: sheet, component: .edge(.init(rawValue: UUID().uuidString))) }
        let references = (0..<2).map { _ in SelectionTarget(sceneNodeID: SceneNodeID()) }
        var session = WorkspaceFaceEditSession(kind: .alignSurface(pairs: [
            .init(edge: edges[0], reference: references[0]), .init(edge: edges[1], reference: references[1]),
        ]))
        session.refitsLayout = true
        let commands = session.commands()
        guard case let .alignSurface(_, _, _, _, _, _, _, firstLayout, _, firstKeeps) = commands[0],
              case let .alignSurface(_, _, _, _, _, _, _, secondLayout, _, secondKeeps) = commands[1] else {
            Issue.record("Expected two alignments.")
            return
        }
        #expect(firstKeeps == false && secondKeeps)
        #expect(firstLayout != nil && secondLayout == nil)
    }

    @Test func theDialogOpensOnPlasticitysDefaults() throws {
        // G0, Tension 0.50 (the kernel's neutral scale 1), influence 0, Boundary Adjacent.
        let targets = (0..<2).map { _ in SelectionTarget(sceneNodeID: SceneNodeID()) }
        var session = WorkspaceFaceEditSession(kind: .alignSurface(pairs: [.init(edge: targets[0], reference: targets[1])]))
        #expect(session.continuity == .positional && session.tension == 0.5)
        #expect(session.inputShapeInfluence == 0 && session.boundaryFlow == .adjacent)
        // Analysis opens on G0 with Scales 10, 10.0 and 0.1.
        #expect(session.analysisMeasure == .position)
        #expect(session.analysisScales == [.position: 10, .tangent: 10, .curvature: 0.1])
        guard case let .alignSurface(_, _, neutral, _, _, _, _, _, _, _) = session.commands()[0] else {
            Issue.record("Expected an alignment.")
            return
        }
        #expect(neutral == 1)
        // The shown tension is 4^(t − 0.5) on the kernel's scale: 0 halves it, 1 doubles it.
        session.tension = 0
        guard case let .alignSurface(_, _, flat, _, _, _, _, _, _, _) = session.commands()[0] else { return }
        session.tension = 1
        guard case let .alignSurface(_, _, full, _, _, _, _, _, _, _) = session.commands()[0] else { return }
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
        guard case let .alignSurface(_, _, first, _, _, _, _, _, _, _) = commands[0],
              case let .alignSurface(_, _, second, _, _, _, _, _, _, _) = commands[1] else {
            Issue.record("Expected two alignments.")
            return
        }
        #expect(first == 1 && second == 2)
    }

    /// Pairs are picked while the dialog runs (Plasticity's align videos modify the selection in
    /// the command): a sheet's edge, then the edge it follows; Control-click takes a pair off with
    /// its own continuity and tension, and the later pairs' settings move down with them.
    @Test func edgesClickedInTheDialogAddAndTakeOffPairs() {
        let targets = (0..<6).map { _ in SelectionTarget(sceneNodeID: SceneNodeID()) }
        var session = WorkspaceFaceEditSession(kind: .alignSurface(pairs: [.init(edge: targets[0], reference: targets[1])]))
        #expect(session.takesEdgePicks)
        session.pick(edge: targets[2], toggles: false)
        #expect(session.pendingAlignEdge == targets[2] && session.missingInput != nil)
        session.pick(edge: targets[3], toggles: false)
        session.pick(edge: targets[4], toggles: false)
        session.pick(edge: targets[5], toggles: false)
        guard case let .alignSurface(pairs) = session.kind else { Issue.record("Expected Align Surface."); return }
        #expect(pairs.map(\.edge) == [targets[0], targets[2], targets[4]] && pairs.map(\.reference) == [targets[1], targets[3], targets[5]])
        #expect(session.pendingAlignEdge == nil && session.missingInput == nil)
        session.pairContinuity = [1: .tangentPlane, 2: .curvature]
        session.pairTension = [2: 0.25]
        // Control-click on the middle pair's reference takes it off; the last pair's settings follow it down.
        session.pick(edge: targets[3], toggles: true)
        guard case let .alignSurface(left) = session.kind else { Issue.record("Expected Align Surface."); return }
        #expect(left.map(\.edge) == [targets[0], targets[4]])
        #expect(session.pairContinuity == [1: .curvature] && session.pairTension == [1: 0.25])
        #expect(session.commands().count == 2)
        // A sheet edge waiting for its reference is dropped by Control-click.
        session.pick(edge: targets[2], toggles: false)
        session.pick(edge: targets[2], toggles: true)
        #expect(session.pendingAlignEdge == nil)
        // With every pair taken off nothing is aligned.
        session.pick(edge: targets[0], toggles: true)
        session.pick(edge: targets[4], toggles: true)
        #expect(session.commands().isEmpty && session.missingInput != nil)
    }
}
