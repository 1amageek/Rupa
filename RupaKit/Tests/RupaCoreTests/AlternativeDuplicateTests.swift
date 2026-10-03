import Foundation
import SwiftCAD
import Testing
@testable import RupaCore

/// Alternative Duplicate on faces copies them beside their body as an object of its own: a solid
/// when they close or bound one with the faces around them (a pocket's plug), a sheet when they
/// bound nothing, the body left as it is. Copy with Placement refuses instances.
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

    /// Two faces of a box bound nothing with the faces around them: they are copied as a sheet.
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

    /// A round pocket's wall and floor do not close, but they bound the plug filling the pocket
    /// with the top it was cut into: the copy is that solid, so the block and the plug together
    /// measure the uncut cube.
    @Test func aPocketsFacesAreCopiedAsThePlugFillingIt() throws {
        let (session, box) = try box()
        let drill = try session.execute(.createExtrudedCircle(
            name: "Drill", plane: .xy, center: SketchPoint(x: .length(0, .meter), y: .length(0, .meter)),
            radius: .length(0.02, .meter), depth: .length(0.1, .meter), direction: .normal
        ))
        let drillNode = try #require(drill.generatedIdentities.sceneNodeIDs.first {
            session.document.productMetadata.sceneNodes[$0]?.reference?.kind == .body
        })
        let start = try DocumentEvaluationContextResolver().evaluatedDocument(document: session.document, failurePrefix: "test")
        let boxFeature = try #require(session.document.productMetadata.sceneNodes[box]?.reference?.featureID)
        let drillFeature = try #require(session.document.productMetadata.sceneNodes[drillNode]?.reference?.featureID)
        func points(of feature: FeatureID, in evaluated: EvaluatedDocument) throws -> [Point3D] {
            guard case let .body(bodyID) = evaluated.subshapes[SubshapeID(featureID: feature, role: GeneratedSubshapeRole.body.rawValue, ordinal: 0)],
                  let body = evaluated.brep.bodies[bodyID] else { throw EditorError(code: .referenceUnresolved, message: "No body.") }
            let faces = body.shellIDs.flatMap { evaluated.brep.shells[$0]?.faceIDs ?? [] }
            return faces.flatMap { evaluated.brep.faces[$0]?.loops ?? [] }.flatMap { evaluated.brep.loops[$0]?.coedges ?? [] }
                .compactMap { evaluated.brep.edges[$0.edgeID].flatMap { evaluated.brep.vertices[$0.startVertexID]?.point } }
        }
        let corners = try points(of: boxFeature, in: start)
        let (low, high) = (try #require(corners.map(\.x).min()), try #require(corners.map(\.x).max()))
        let (south, north) = (try #require(corners.map(\.y).min()), try #require(corners.map(\.y).max()))
        let top = try #require(corners.map(\.z).max())
        let drillBottom = try #require(try points(of: drillFeature, in: start).map(\.z).min())
        let floor = top - 0.04
        // The drill stands in the middle of the top, its bottom 40 mm down.
        _ = try session.execute(.setSceneNodeTransform(id: drillNode, localTransform: try Transform3D.translation(
            Vector3D(x: (low + high) / 2, y: (south + north) / 2, z: floor - drillBottom)
        )))
        let cut = try session.execute(.createBoolean(
            name: "Pocket", targets: [BooleanTargetReference(featureID: boxFeature)],
            tools: [BooleanToolReference(featureID: drillFeature)], operation: .difference, keepTools: false
        ))
        let pocketed = try #require(cut.generatedIdentities.featureIDs.last)
        let evaluated = try DocumentEvaluationContextResolver().evaluatedDocument(document: session.document, failurePrefix: "test")
        let pocketIdentities = Set(evaluated.subshapes.entries.compactMap { key, value -> String? in
            guard key.featureID == pocketed, case let .face(faceID) = value, let face = evaluated.brep.faces[faceID] else { return nil }
            if case .cylinder = evaluated.brep.geometry.surfaces[face.surfaceID] { return GeneratedSubshapeIdentity.string(for: key) }
            let heights = face.loops.flatMap { evaluated.brep.loops[$0]?.coedges ?? [] }
                .compactMap { evaluated.brep.edges[$0.edgeID].flatMap { evaluated.brep.vertices[$0.startVertexID]?.point.z } }
            return heights.isEmpty == false && heights.allSatisfy { abs($0 - floor) < 1e-9 } ? GeneratedSubshapeIdentity.string(for: key) : nil
        })
        let pocketNode = try #require(session.document.productMetadata.sceneNodes.values.first { $0.reference?.featureID == pocketed }).id
        let targets = try TopologySnapshotService().snapshot(document: session.document).entries
            .filter { $0.kind == .face && $0.sceneNodeID == pocketNode.description && pocketIdentities.contains($0.subshapeID) }
            .compactMap { $0.selectionTarget() }
        #expect(targets.count >= 2)
        _ = try session.execute(.duplicateBodyFaces(name: "Alternative Duplicate", targets: targets))
        let copy = try #require(copies(session).first)
        #expect(copy.object?.geometryRole == .solid)
        #expect(abs(try totals(session).solidVolumeCubicMeters - cube) < 1e-9)
        #expect(session.evaluationStatus == .valid)
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
