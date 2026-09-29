import Foundation
import SwiftCAD
import Testing
@testable import RupaCore

/// Deform Solid and Sheet carries bodies from a reference face onto a target face through
/// Swift-CAD's Wrap, each face read where its object is displayed. Without Keep Tools the deformed
/// body takes over the body's object; with it the body stays and the copy is shown beside it.
@MainActor
@Suite struct BodyDeformationTests {
    private let cube = 0.1 * 0.1 * 0.1

    private struct Fixture {
        var session: EditorSession
        /// The body deformed, standing on the origin's xy plane.
        var body: SceneNodeID
        /// A body 0.3 m lower and one 0.5 m higher, with the same footprint.
        var lower: SceneNodeID
        var upper: SceneNodeID
    }

    private func fixture() throws -> Fixture {
        let session = EditorSession()
        for name in ["Body", "Lower", "Upper"] {
            _ = try session.execute(.createExtrudedRectangle(
                name: name, plane: .xy,
                width: .length(0.1, .meter), height: .length(0.1, .meter),
                depth: .length(0.1, .meter), direction: .normal
            ))
        }
        func node(_ name: String) throws -> SceneNodeID {
            try #require(session.document.productMetadata.sceneNodes.values.first {
                $0.name.hasPrefix(name) && $0.reference?.kind == .body
            }).id
        }
        let fixture = Fixture(session: session, body: try node("Body"), lower: try node("Lower"), upper: try node("Upper"))
        _ = try session.execute(.setSceneNodeTransform(
            id: fixture.lower, localTransform: try Transform3D.translation(Vector3D(x: 0, y: 0, z: -0.3))
        ))
        _ = try session.execute(.setSceneNodeTransform(
            id: fixture.upper, localTransform: try Transform3D.translation(Vector3D(x: 0, y: 0, z: 0.5))
        ))
        return fixture
    }

    private func faces(of node: SceneNodeID, in session: EditorSession) throws -> [TopologySummaryResult.Entry] {
        try TopologySnapshotService().snapshot(document: session.document).entries
            .filter { $0.kind == .face && $0.sceneNodeID == node.description }
    }

    private func top(of node: SceneNodeID, in session: EditorSession) throws -> SelectionTarget {
        try #require(try faces(of: node, in: session).first { ($0.normal?.z ?? 0) > 0.5 }?.selectionTarget())
    }

    /// The lowest and highest face centers of `node`'s body, in world z.
    private func heights(of node: SceneNodeID, in session: EditorSession) throws -> (Double, Double) {
        let z = try faces(of: node, in: session).compactMap { $0.center?.z }
        return (try #require(z.min()), try #require(z.max()))
    }

    private func volume(_ session: EditorSession) throws -> Double {
        try MeasurementService().measure(document: session.document, ruler: .standard(for: .meter)).totals.solidVolumeCubicMeters
    }

    @Test func aBodyGoesFromOneFaceToAnotherWhereBothAreDisplayed() throws {
        let f = try fixture()
        // The body stands 0.2 m above the lower body's top (world z −0.2) and lands as far above
        // the upper body's top (world z 0.6).
        let options = CurveDeformationOptions()
        _ = try f.session.execute(.deformBodies(
            targets: [f.body], referenceFace: try top(of: f.lower, in: f.session),
            targetFace: try top(of: f.upper, in: f.session), options: options
        ))
        let node = try #require(f.session.document.productMetadata.sceneNodes[f.body])
        guard let featureID = node.reference?.featureID,
              case .wrap = f.session.document.cadDocument.designGraph.nodes[featureID]?.operation else {
            Issue.record("The body's object does not show the Wrap.")
            return
        }
        let (low, high) = try heights(of: f.body, in: f.session)
        #expect(abs(low - 0.8) < 1e-6 && abs(high - 0.9) < 1e-6)
        #expect(abs(try volume(f.session) - 3 * cube) < 1e-9)
        #expect(f.session.evaluationStatus == .valid)
        try expectEveryBodyObjectPresentsAnEvaluatedBody(f.session.document)
    }

    @Test func keepToolsLeavesTheBodyAndShowsTheCopyBesideIt() throws {
        let f = try fixture()
        var options = CurveDeformationOptions()
        options.keepsTools = true
        options.offsetN = .length(0.05, .meter)
        let source = try #require(f.session.document.productMetadata.sceneNodes[f.body]?.reference?.featureID)
        _ = try f.session.execute(.deformBodies(
            targets: [f.body], referenceFace: try top(of: f.lower, in: f.session),
            targetFace: try top(of: f.lower, in: f.session), options: options
        ))
        #expect(f.session.document.productMetadata.sceneNodes[f.body]?.reference?.featureID == source)
        let copy = try #require(f.session.document.productMetadata.sceneNodes.values.first { $0.name == "Body Deformed" })
        let (low, high) = try heights(of: copy.id, in: f.session)
        #expect(abs(low - 0.05) < 1e-6 && abs(high - 0.15) < 1e-6)
        #expect(abs(try volume(f.session) - 4 * cube) < 1e-9)
        try expectEveryBodyObjectPresentsAnEvaluatedBody(f.session.document)
    }

    @Test func replacingBothBodiesThatHoldThePickedFacesIsRefusedWithoutAChange() throws {
        let f = try fixture()
        let before = f.session.document.cadDocument.designGraph.nodes.count
        #expect(throws: (any Error).self) {
            _ = try f.session.execute(.deformBodies(
                targets: [f.lower, f.upper], referenceFace: try top(of: f.lower, in: f.session),
                targetFace: try top(of: f.upper, in: f.session), options: CurveDeformationOptions()
            ))
        }
        var flat = CurveDeformationOptions()
        flat.scaleN = 0
        #expect(throws: (any Error).self) {
            _ = try f.session.execute(.deformBodies(
                targets: [f.body], referenceFace: try top(of: f.lower, in: f.session),
                targetFace: try top(of: f.upper, in: f.session), options: flat
            ))
        }
        #expect(f.session.document.cadDocument.designGraph.nodes.count == before)
    }
}
