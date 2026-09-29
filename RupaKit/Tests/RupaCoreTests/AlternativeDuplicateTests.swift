import Foundation
import SwiftCAD
import Testing
@testable import RupaCore

/// Alternative Duplicate on faces copies them beside their body as an object of its own: a solid
/// when they close, a sheet when they do not, the body left as it is. Copy with Placement refuses
/// instances.
@MainActor
@Suite struct AlternativeDuplicateTests {
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

    private func totals(_ session: EditorSession) throws -> MeasurementResult.Totals {
        try MeasurementService().measure(document: session.document, ruler: .standard(for: .meter)).totals
    }

    private func copies(_ session: EditorSession) -> [SceneNode] {
        session.document.productMetadata.sceneNodes.values.filter { $0.name == "Alternative Duplicate" }
    }

    @Test func everyFaceOfABodyIsCopiedAsASolid() throws {
        let (session, box) = try box()
        let all = try faces(of: box, in: session)
        #expect(all.count == 6)
        let result = try session.execute(.duplicateBodyFaces(name: "Alternative Duplicate", targets: all))
        let copy = try #require(copies(session).first)
        #expect(copy.object?.geometryRole == .solid)
        #expect(result.generatedIdentities.sceneNodeIDs.contains(copy.id))
        #expect(abs(try totals(session).solidVolumeCubicMeters - 2 * cube) < 1e-9)
        #expect(session.evaluationStatus == .valid)
        try expectEveryBodyObjectPresentsAnEvaluatedBody(session.document)
    }

    @Test func facesThatDoNotCloseAreCopiedAsASheet() throws {
        let (session, box) = try box()
        let two = Array(try faces(of: box, in: session).prefix(2))
        _ = try session.execute(.duplicateBodyFaces(name: "Alternative Duplicate", targets: two))
        let copy = try #require(copies(session).first)
        #expect(copy.object?.geometryRole == .surface)
        #expect(abs(try totals(session).solidVolumeCubicMeters - cube) < 1e-9)
        let feature = try #require(copy.reference?.featureID)
        let evaluated = try DocumentEvaluationContextResolver().evaluatedDocument(document: session.document, failurePrefix: "test")
        guard case let .body(bodyID) = evaluated.subshapes[SubshapeID(featureID: feature, role: GeneratedSubshapeRole.body.rawValue, ordinal: 0)],
              let body = evaluated.brep.bodies[bodyID] else {
            Issue.record("The copy has no evaluated body.")
            return
        }
        #expect(body.kind == .sheet)
        #expect(body.shellIDs.flatMap { evaluated.brep.shells[$0]?.faceIDs ?? [] }.count == 2)
    }

    @Test func somethingOtherThanFacesIsRefusedWithoutAChange() throws {
        let (session, box) = try box()
        let before = session.document
        #expect(throws: (any Error).self) {
            _ = try session.execute(.duplicateBodyFaces(name: "Alternative Duplicate", targets: [SelectionTarget(sceneNodeID: box)]))
        }
        #expect(session.document.cadDocument.designGraph == before.cadDocument.designGraph)
    }

    @Test func copyWithPlacementRefusesInstances() throws {
        let (session, box) = try box()
        let result = try session.execute(.placeSceneNodes(ids: [box], placements: [.identity], output: .componentInstance, boolean: nil))
        let instance = try #require(result.generatedIdentities.sceneNodeIDs.first {
            session.document.productMetadata.sceneNodes[$0]?.reference?.kind == .componentInstance
        })
        let metadata = session.document.productMetadata
        #expect(metadata.placementCopyRefusal(for: [box]) == nil)
        #expect(metadata.placementCopyRefusal(for: [instance])?.code == .commandInvalid)
    }
}
