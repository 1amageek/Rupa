import Foundation
import SwiftCAD
import Testing
@testable import RupaCore

/// Join sews sheet objects into one where their edges meet exactly, a solid when they close, each
/// joined where it is displayed; Unjoin separates chosen faces, or every face, into sheets that
/// take the body's place.
@MainActor
@Suite struct JoinUnjoinCommandTests {
    private let cube = 0.1 * 0.1 * 0.1

    private func box() throws -> (EditorSession, SceneNodeID) {
        let session = EditorSession()
        _ = try session.execute(.createExtrudedRectangle(
            name: "Box", plane: .xy,
            width: .length(0.1, .meter), height: .length(0.1, .meter),
            depth: .length(0.1, .meter), direction: .normal
        ))
        let node = try #require(session.document.productMetadata.sceneNodes.values.first {
            $0.name.hasPrefix("Box") && $0.reference?.kind == .body
        }).id
        return (session, node)
    }

    private func faces(of node: SceneNodeID, in session: EditorSession) throws -> [SelectionTarget] {
        try TopologySnapshotService().snapshot(document: session.document).entries
            .filter { $0.kind == .face && $0.sceneNodeID == node.description }
            .compactMap { $0.selectionTarget() }
    }

    /// Every face of a box copied as a sheet object of its own; the box is taken away.
    private func faceSheets() throws -> (EditorSession, [SceneNodeID]) {
        let (session, box) = try box()
        _ = try session.execute(.unjoinShells(name: "Unjoin", targets: [SelectionTarget(sceneNodeID: box)]))
        let sheets = session.document.productMetadata.sceneNodes.values
            .filter { $0.reference?.kind == .body && $0.object?.geometryRole == .surface }
            .map(\.id)
        return (session, sheets)
    }

    private func bodyObjects(_ session: EditorSession) -> [SceneNode] {
        session.document.productMetadata.sceneNodes.values.filter { $0.reference?.kind == .body }
    }

    private func totals(_ session: EditorSession) throws -> MeasurementResult.Totals {
        try MeasurementService().measure(document: session.document, ruler: .standard(for: .meter)).totals
    }

    private func evaluatedFaceCount(of node: SceneNode, in session: EditorSession) throws -> Int {
        let feature = try #require(node.reference?.featureID)
        let evaluated = try DocumentEvaluationContextResolver().evaluatedDocument(document: session.document, failurePrefix: "test")
        guard case let .body(bodyID) = evaluated.subshapes[SubshapeID(featureID: feature, role: GeneratedSubshapeRole.body.rawValue, ordinal: 0)],
              let body = evaluated.brep.bodies[bodyID] else {
            throw EditorError(code: .referenceUnresolved, message: "No evaluated body.")
        }
        return body.shellIDs.flatMap { evaluated.brep.shells[$0]?.faceIDs ?? [] }.count
    }

    @Test(.timeLimit(.minutes(1)))
    func unjoinShellsMakesEveryFaceASheetInTheBodysPlace() throws {
        let (session, sheets) = try faceSheets()
        #expect(sheets.count == 6)
        #expect(bodyObjects(session).count == 6)
        #expect(bodyObjects(session).allSatisfy { $0.object?.geometryRole == .surface })
        #expect(abs(try totals(session).solidVolumeCubicMeters) < 1e-12)
        #expect(session.evaluationStatus == .valid)
        try expectEveryBodyObjectPresentsAnEvaluatedBody(session.document)
    }

    @Test(.timeLimit(.minutes(1)))
    func sheetsThatCloseJoinIntoASolid() throws {
        let (session, sheets) = try faceSheets()
        _ = try session.execute(.joinSheets(name: "Join", targets: sheets.map { SelectionTarget(sceneNodeID: $0) }))
        let objects = bodyObjects(session)
        #expect(objects.count == 1)
        #expect(objects.first?.object?.geometryRole == .solid)
        #expect(abs(try totals(session).solidVolumeCubicMeters - cube) < 1e-9)
        #expect(session.evaluationStatus == .valid)
        try expectEveryBodyObjectPresentsAnEvaluatedBody(session.document)
    }

    @Test(.timeLimit(.minutes(1)))
    func sheetsThatMeetJoinIntoOneSheetAndOthersAreRefused() throws {
        let (session, box) = try box()
        let all = try faces(of: box, in: session)
        _ = try session.execute(.unjoinShells(name: "Unjoin", targets: [SelectionTarget(sceneNodeID: box)]))
        let sheets = bodyObjects(session)
        #expect(all.count == 6)
        var joinedPair = false
        for first in sheets {
            for second in sheets where second.id != first.id {
                let before = session.document
                do {
                    _ = try session.execute(.joinSheets(name: "Join", targets: [
                        SelectionTarget(sceneNodeID: first.id), SelectionTarget(sceneNodeID: second.id),
                    ]))
                } catch {
                    // Opposite faces share no edge: the join is refused and nothing changes.
                    #expect(session.document.cadDocument.designGraph == before.cadDocument.designGraph)
                    continue
                }
                let joined = try #require(session.document.productMetadata.sceneNodes[first.id])
                #expect(joined.object?.geometryRole == .surface)
                #expect(try evaluatedFaceCount(of: joined, in: session) == 2)
                #expect(session.document.productMetadata.sceneNodes[second.id] == nil)
                joinedPair = true
                break
            }
            if joinedPair { break }
        }
        #expect(joinedPair)
    }

    @Test(.timeLimit(.minutes(1)))
    func sheetsJoinWhereTheyAreDisplayed() throws {
        let (session, sheets) = try faceSheets()
        let away = try Transform3D.translation(Vector3D(x: 1, y: 0, z: 0))
        // One sheet moved away no longer meets the others.
        _ = try session.execute(.setSceneNodeTransform(id: sheets[0], localTransform: away))
        let before = session.document
        #expect(throws: (any Error).self) {
            _ = try session.execute(.joinSheets(name: "Join", targets: sheets.map { SelectionTarget(sceneNodeID: $0) }))
        }
        #expect(session.document.cadDocument.designGraph == before.cadDocument.designGraph)
        // All of them moved alike still meet where they are displayed.
        for sheet in sheets.dropFirst() {
            _ = try session.execute(.setSceneNodeTransform(id: sheet, localTransform: away))
        }
        _ = try session.execute(.joinSheets(name: "Join", targets: sheets.map { SelectionTarget(sceneNodeID: $0) }))
        let solid = try #require(bodyObjects(session).first)
        #expect(bodyObjects(session).count == 1)
        #expect(solid.object?.geometryRole == .solid)
        #expect(abs(try totals(session).solidVolumeCubicMeters - cube) < 1e-9)
    }

    @Test(.timeLimit(.minutes(1)))
    func aSolidIsNotJoinedAsASheet() throws {
        let (session, box) = try box()
        let face = try #require(try faces(of: box, in: session).first)
        _ = try session.execute(.duplicateBodyFaces(name: "Copy", targets: [face]))
        let sheet = try #require(bodyObjects(session).first { $0.object?.geometryRole == .surface })
        let before = session.document
        #expect(throws: EditorError.self) {
            _ = try session.execute(.joinSheets(name: "Join", targets: [
                SelectionTarget(sceneNodeID: box), SelectionTarget(sceneNodeID: sheet.id),
            ]))
        }
        #expect(session.document.cadDocument.designGraph == before.cadDocument.designGraph)
    }

    @Test(.timeLimit(.minutes(1)))
    func unjoinFacesSeparatesTheChosenFacesAndKeepsTheRestInPieces() throws {
        let (session, box) = try box()
        let all = try faces(of: box, in: session)
        let snapshot = try TopologySnapshotService().snapshot(document: session.document)
        // The four side faces: the top and bottom that remain do not touch.
        let sides = snapshot.entries.filter { entry in
            entry.kind == .face && entry.sceneNodeID == box.description && abs(entry.surfaceNormal?.z ?? 1) < 0.5
        }.compactMap { $0.selectionTarget() }
        #expect(all.count == 6)
        #expect(sides.count == 4)
        _ = try session.execute(.unjoinFaces(name: "Unjoin", targets: sides))
        let objects = bodyObjects(session)
        #expect(session.document.productMetadata.sceneNodes[box] == nil)
        #expect(objects.count == 6)
        #expect(objects.allSatisfy { $0.object?.geometryRole == .surface })
        #expect(try objects.map { try evaluatedFaceCount(of: $0, in: session) }.allSatisfy { $0 == 1 })
        #expect(session.evaluationStatus == .valid)
        try expectEveryBodyObjectPresentsAnEvaluatedBody(session.document)
    }

    @Test(.timeLimit(.minutes(1)))
    func unjoinFacesKeepsAConnectedRemainderAsOneSheet() throws {
        let (session, box) = try box()
        let top = try #require(try TopologySnapshotService().snapshot(document: session.document).entries.first { entry in
            entry.kind == .face && entry.sceneNodeID == box.description && abs(entry.surfaceNormal?.z ?? 0) > 0.5 && (entry.center?.z ?? 0) > 0.05
        }?.selectionTarget())
        _ = try session.execute(.unjoinFaces(name: "Unjoin", targets: [top]))
        let objects = bodyObjects(session)
        #expect(objects.count == 2)
        #expect(Set(try objects.map { try evaluatedFaceCount(of: $0, in: session) }) == [1, 5])
    }
}
