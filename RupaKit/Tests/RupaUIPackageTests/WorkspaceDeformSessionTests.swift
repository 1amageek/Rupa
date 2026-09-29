import RupaCore
import SwiftCAD
import RupaRendering
import Testing
@testable import RupaUI

/// Deform's dialog picks the reference face, then the target face (a later click replaces the
/// target), and submits Deform Curve only once both are picked.
@Test func theDeformDialogPicksReferenceThenTargetAndSubmitsWithBoth() throws {
    let curve = SelectionTarget(sceneNodeID: SceneNodeID(), component: .object)
    #expect(WorkspaceDeformSession(selectedCurves: []) == nil)
    var session = try #require(WorkspaceDeformSession(selectedCurves: [curve]))
    #expect(session.step == .referenceFace && session.command == nil)
    let reference = SelectionTarget(sceneNodeID: SceneNodeID(), component: .object)
    let first = SelectionTarget(sceneNodeID: SceneNodeID(), component: .object)
    let second = SelectionTarget(sceneNodeID: SceneNodeID(), component: .object)
    session.pick(face: reference)
    #expect(session.step == .targetFace && session.command == nil)
    session.pick(face: first)
    session.pick(face: second)
    #expect(session.step == .options)
    session.options.flipsNormal = true
    session.offsetNMeters = 0.002
    guard case .deformCurves(let targets, let referenceFace, let targetFace, let options)? = session.command else {
        Issue.record("The dialog submitted no Deform Curve.")
        return
    }
    #expect(targets == [curve] && referenceFace == reference && targetFace == second)
    #expect(options.flipsNormal && options.offsetN == .length(0.002, .meter))
}

/// With body objects selected the same dialog submits Deform Solid and Sheet; a selection of
/// curves and bodies together opens no dialog.
@Test func theDeformDialogOnBodiesSubmitsDeformBodies() throws {
    let body = SceneNodeID()
    let curve = SelectionTarget(sceneNodeID: SceneNodeID(), component: .object)
    #expect(WorkspaceDeformSession(selectedCurves: [curve], selectedBodies: [body]) == nil)
    var session = try #require(WorkspaceDeformSession(selectedCurves: [], selectedBodies: [body]))
    let reference = SelectionTarget(sceneNodeID: SceneNodeID(), component: .object)
    let target = SelectionTarget(sceneNodeID: SceneNodeID(), component: .object)
    session.pick(face: reference)
    session.pick(face: target)
    session.options.keepsTools = true
    guard case .deformBodies(let targets, let referenceFace, let targetFace, let options)? = session.command else {
        Issue.record("The dialog submitted no Deform Solid and Sheet.")
        return
    }
    #expect(targets == [body] && referenceFace == reference && targetFace == target && options.keepsTools)
    #expect(session.subjectDescription == "1 body")
}

/// Deform's clicks pick faces whatever the selection scope: the viewport resolves them to faces
/// only while the dialog runs.
@Test func theDeformDialogMakesClicksPickFaces() throws {
    let session = try #require(WorkspaceDeformSession(selectedCurves: [], selectedBodies: [SceneNodeID()]))
    #expect(session.viewportHitPolicy == .face)
}
