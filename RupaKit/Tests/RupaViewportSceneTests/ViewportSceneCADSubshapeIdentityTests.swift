import Foundation
import RupaCore
import RupaViewportScene
import SwiftCAD
import Testing

@MainActor
@Test(.timeLimit(.minutes(1)))
func extrudeBodyItemCarriesThePreparedCADSubshapeIdentityOfItsEvaluatedBody() throws {
    let session = EditorSession()
    _ = try #require(session.createDefaultExtrudedRectangle())
    let bodyFeatureID = try #require(session.document.cadDocument.designGraph.order.last)

    let scene = ViewportSceneBuilder().build(
        document: session.document,
        ruler: .standard(for: .meter),
        evaluationPolicy: .evaluateOnDemand
    )
    let component = try #require(bodyComponent(in: scene, featureID: bodyFeatureID))

    let mesh = try #require(component.mesh)
    let topology = try #require(component.topology)
    #expect(!topology.meshFaceRuns.isEmpty)

    // Every recorded sub-shape names a kernel sub-shape. A projected box face
    // name here would mean the item lost the evaluation's identity and was
    // renamed after the fact.
    for face in topology.faces {
        #expect(face.componentID.generatedTopologySubshapeID != nil)
    }
    for edge in topology.edges {
        #expect(edge.componentID.generatedTopologySubshapeID != nil)
    }
    for vertex in topology.vertices {
        #expect(vertex.componentID.generatedTopologySubshapeID != nil)
    }

    // The runs index this item's own mesh. Carrying a run list that addresses
    // triangles the carried mesh does not contain would name sub-shapes on
    // geometry nobody draws, which is the failure the single-snapshot argument
    // exists to prevent.
    let triangleCount = mesh.indices.count / 3
    #expect(mesh.indices.count.isMultiple(of: 3))
    for run in topology.meshFaceRuns {
        #expect(run.componentID.generatedTopologySubshapeID != nil)
        #expect(!run.triangleRange.isEmpty)
        #expect(run.triangleRange.lowerBound >= 0)
        #expect(run.triangleRange.upperBound <= triangleCount)
        #expect(topology.componentID(forTriangle: run.triangleRange.lowerBound) == run.componentID)
        #expect(topology.componentID(forTriangle: run.triangleRange.upperBound - 1) == run.componentID)
    }
}

@MainActor
@Test(.timeLimit(.minutes(1)))
func extrudeBodyItemCarriesNoCADSubshapeIdentityWithoutASuppliedEvaluation() throws {
    let session = EditorSession()
    _ = try #require(session.createDefaultExtrudedRectangle())
    let bodyFeatureID = try #require(session.document.cadDocument.designGraph.order.last)

    let scene = ViewportSceneBuilder().build(
        document: session.document,
        ruler: .standard(for: .meter),
        evaluationPolicy: .suppliedOnly
    )
    let component = try #require(bodyComponent(in: scene, featureID: bodyFeatureID))

    // Without an evaluation there is no snapshot to take, so neither half of
    // the pair appears. Carrying one without the other is the state the
    // scene-builder contract forbids.
    #expect(component.mesh == nil)
    #expect(component.topology == nil)
}

@MainActor
@Test(.timeLimit(.minutes(1)))
func carriedCircleExtrudeFaceIdentitiesResolveToKernelBodyFaces() throws {
    let session = EditorSession()
    _ = try #require(session.createDefaultExtrudedCircle())
    let bodyFeatureID = try #require(session.document.cadDocument.designGraph.order.last)

    let scene = ViewportSceneBuilder().build(
        document: session.document,
        ruler: .standard(for: .meter),
        evaluationPolicy: .evaluateOnDemand
    )
    let item = try #require(bodyItem(in: scene, featureID: bodyFeatureID))
    guard case .body(let component) = item.kind else {
        Issue.record("The circle extrude item is not a body item.")
        return
    }
    let topology = try #require(component.topology)
    let sceneNodeID = try #require(item.sceneNodeID)
    #expect(!topology.faces.isEmpty)

    // A cylinder's side face has no projected box name that direct editing can
    // offset, so the box vocabulary answered it with a face that throws. The
    // carried kernel identity resolves through the generated-topology resolver
    // instead, and the three faces of a circle extrude are its two caps and
    // its side.
    let resolver = GeneratedTopologySelectionResolver()
    var resolved: Set<BodyFace> = []
    for face in topology.faces {
        let target = SelectionTarget(sceneNodeID: sceneNodeID, component: .face(face.componentID))
        resolved.insert(try resolver.bodyFace(for: target, in: session.document))
    }
    #expect(resolved == [.front, .back, .side])
}

private func bodyItem(
    in scene: ViewportScene,
    featureID: FeatureID
) -> ViewportSceneItem? {
    for item in scene.items where item.featureID == featureID {
        guard case .body = item.kind else {
            continue
        }
        return item
    }
    return nil
}

private func bodyComponent(
    in scene: ViewportScene,
    featureID: FeatureID
) -> ViewportBodyComponent? {
    guard let item = bodyItem(in: scene, featureID: featureID),
          case .body(let component) = item.kind else {
        return nil
    }
    return component
}
