import Testing
import RupaCore
import SwiftCAD
@testable import RupaUI

/// Push Face, Draft Face and Match Face take faces as clicks while the dialog runs, as
/// Plasticity's do: Push Face's face to push onto, Draft Face's reference first, Match Face's
/// reference in the dialog.
@Suite("Face edit session picking")
struct WorkspaceFaceEditSessionPickTests {
    @Test func draftFacePicksTheReferenceFirstThenTheFaces() throws {
        let faces = (0..<3).map { _ in SelectionTarget(sceneNodeID: SceneNodeID()) }
        var session = WorkspaceFaceEditSession(kind: .draft(faces: [], neutral: nil))
        // Degrees open at 0, so nothing runs until the faces and an angle are set.
        #expect(session.draftAngleDegrees == 0)
        #expect(session.missingInput == "Draft Face: click the reference face.")
        #expect(session.commands().isEmpty)
        session.pick(face: faces[0], toggles: false)
        #expect(session.kind == .draft(faces: [], neutral: faces[0]))
        session.pick(face: faces[1], toggles: false)
        session.pick(face: faces[2], toggles: true)
        // Clicking the reference again or a drafted face without Control keeps them.
        session.pick(face: faces[0], toggles: true)
        session.pick(face: faces[1], toggles: false)
        #expect(session.kind == .draft(faces: [faces[1], faces[2]], neutral: faces[0]))
        #expect(session.missingInput == "Draft Face: set Degrees.")
        session.draftAngleDegrees = 5
        guard case let .draftBodyFaces(targets, neutral, _, _, _)? = session.commands().first else {
            Issue.record("Expected a draft.")
            return
        }
        #expect(targets == [faces[1], faces[2]] && neutral == faces[0])
        // Control-click takes a drafted face back off.
        session.pick(face: faces[1], toggles: true)
        #expect(session.kind == .draft(faces: [faces[2]], neutral: faces[0]))
    }

    @Test func matchFaceTakesItsReferenceInTheDialog() throws {
        let faces = (0..<3).map { _ in SelectionTarget(sceneNodeID: SceneNodeID()) }
        var session = WorkspaceFaceEditSession(kind: .match(faces: [faces[0]], reference: nil))
        #expect(session.missingInput == "Match Face: click the face to match onto.")
        #expect(session.commands().isEmpty)
        session.pick(face: faces[1], toggles: false)
        session.pick(face: faces[2], toggles: false)
        #expect(session.kind == .match(faces: [faces[0]], reference: faces[2]))
        // Control-click adds a face to match, and takes it back off.
        session.pick(face: faces[1], toggles: true)
        #expect(session.kind == .match(faces: [faces[0], faces[1]], reference: faces[2]))
        session.pick(face: faces[1], toggles: true)
        guard case let .matchFaces(targets, reference, _, _)? = session.commands().first else {
            Issue.record("Expected a match.")
            return
        }
        #expect(targets == [faces[0]] && reference == faces[2])
    }

    @Test func pushFacePushesOntoAClickedFaceAndBackByItsArrow() throws {
        let faces = (0..<2).map { _ in SelectionTarget(sceneNodeID: SceneNodeID()) }
        var session = WorkspaceFaceEditSession(kind: .push(faces: [faces[0]]))
        // The Distance opens at 0, so nothing is pushed until it is set or a face is clicked.
        #expect(session.distanceMeters == 0 && session.commands().isEmpty && session.missingInput != nil)
        // The pushed face itself is not a face to push onto.
        session.pick(face: faces[0], toggles: false)
        #expect(session.kind == .push(faces: [faces[0]]))
        // A clicked face is the dependant offset: the face goes onto it.
        session.pick(face: faces[1], toggles: false)
        guard case let .matchFaces(targets, reference, _, _)? = session.commands().first else {
            Issue.record("Expected the face matched onto the clicked face.")
            return
        }
        #expect(targets == [faces[0]] && reference == faces[1])
        // The face's arrow pushes it by a distance again.
        session.setPushDistance(0.002)
        guard case let .pushFaces(pushed, distance, _, _)? = session.commands().first else {
            Issue.record("Expected a push.")
            return
        }
        #expect(pushed == [faces[0]] && distance == .length(0.002, .meter))
    }
}
