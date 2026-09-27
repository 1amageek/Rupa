import Foundation
import SwiftCAD
import Testing
@testable import RupaCore

/// Create Instance: an instance of the selection appears exactly where the selection is, linked to
/// it as its component definition, and the command reports the instance node it made.
@MainActor
@Suite struct CreateInstanceTests {
    private func mm(_ value: Double) -> CADExpression { .length(value, .millimeter) }

    private func node(of featureID: FeatureID, in session: EditorSession) throws -> SceneNodeID {
        try #require(session.document.productMetadata.sceneNodes.values.first {
            $0.reference?.featureID == featureID
        }).id
    }

    /// World origins where an occurrence of `source` is shown under `node`.
    private func shownOrigins(of source: SceneNodeID, under node: SceneNodeID, in session: EditorSession) throws -> [Point3D] {
        try SceneNodeHierarchy(metadata: session.document.productMetadata).resolvedOccurrences().filter {
            $0.sceneNodeID == node && $0.sourceSceneNodeID == source
        }.map { try $0.worldTransform.applied(to: .origin) }
    }

    private func createInstance(of source: SceneNodeID, in session: EditorSession) throws -> SceneNodeID {
        let definitions = session.document.productMetadata.componentDefinitions.count
        let result = try session.execute(.placeSceneNodes(
            ids: [source], placements: [.identity], output: .componentInstance, boolean: nil
        ))
        let instances = result.generatedIdentities.sceneNodeIDs.filter {
            session.document.productMetadata.sceneNodes[$0]?.reference?.kind == .componentInstance
        }
        #expect(instances.count == 1)
        #expect(session.document.productMetadata.componentDefinitions.count == definitions + 1)
        return try #require(instances.first)
    }

    @Test func aBodysInstanceAppearsWhereTheBodyIs() throws {
        let session = EditorSession()
        _ = try session.execute(.createExtrudedRectangle(
            name: "Box", plane: .xy, width: mm(40), height: mm(20), depth: mm(10), direction: .normal
        ))
        let featureID = try #require(session.document.cadDocument.designGraph.order.last)
        let box = try node(of: featureID, in: session)
        _ = try session.execute(.transformSceneNodes(
            ids: [box], worldDelta: try Transform3D.translation(Vector3D(x: 0.3, y: -0.2, z: 0.1)),
            compensatingInstances: false
        ))
        let boxOrigin = try SceneNodeHierarchy(metadata: session.document.productMetadata)
            .worldTransform(of: box).applied(to: .origin)

        let instance = try createInstance(of: box, in: session)

        let shown = try #require(try shownOrigins(of: box, under: instance, in: session).first)
        #expect((shown - boxOrigin).length < 1e-12)
        #expect(session.document.productMetadata.sceneNodes[box] != nil)
        _ = try session.document.validate()
    }

    @Test func aCurvesInstanceAppearsWhereTheCurveIs() throws {
        let session = EditorSession()
        let line = SketchEntityID()
        _ = try session.execute(.createSketch(
            name: "Curve",
            sketch: Sketch(plane: .xy, entities: [
                line: .line(SketchLine(start: SketchPoint(x: mm(0), y: mm(0)), end: SketchPoint(x: mm(30), y: mm(10)))),
            ]),
            geometryRole: .curve
        ))
        let featureID = try #require(session.document.cadDocument.designGraph.order.last)
        let curve = try node(of: featureID, in: session)
        let curveOrigin = try SceneNodeHierarchy(metadata: session.document.productMetadata)
            .worldTransform(of: curve).applied(to: .origin)

        let instance = try createInstance(of: curve, in: session)

        let shown = try #require(try shownOrigins(of: curve, under: instance, in: session).first)
        #expect((shown - curveOrigin).length < 1e-12)
        _ = try session.document.validate()
    }
}
