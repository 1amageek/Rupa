import Testing
import SwiftCAD
@testable import RupaCore

@MainActor
@Test func generatedTopologySelectionResolverRoundTripsRectangleFacesAndCornerEdges() async throws {
    let session = EditorSession()
    _ = try #require(session.createDefaultExtrudedRectangle())
    let bodyFeatureID = try #require(session.document.cadDocument.designGraph.order.last)
    let sceneNodeID = try #require(resolverSceneNodeID(for: bodyFeatureID, in: session.document))
    let resolver = GeneratedTopologySelectionResolver()

    for bodyFace in BodyFace.allCasesForTesting {
        let componentID = try #require(
            try resolver.componentID(
                for: sceneNodeID,
                bodyFace: bodyFace,
                in: session.document
            )
        )
        #expect(componentID.isStableTopology)
        let target = SelectionTarget(sceneNodeID: sceneNodeID, component: .face(componentID))
        let resolvedFace = try resolver.bodyFace(for: target, in: session.document)
        #expect(resolvedFace == bodyFace)
    }

    for cornerEdge in BodyCornerEdge.allCasesForTesting {
        let componentID = try #require(
            try resolver.componentID(
                for: sceneNodeID,
                cornerEdge: cornerEdge,
                in: session.document
            )
        )
        #expect(componentID.isStableTopology)
        let target = SelectionTarget(sceneNodeID: sceneNodeID, component: .edge(componentID))
        let resolvedEdge = try resolver.cornerEdge(for: target, in: session.document)
        #expect(resolvedEdge == cornerEdge)
    }

    for cornerVertex in BodyCornerVertex.allCases {
        let componentID = try #require(
            try resolver.componentID(
                for: sceneNodeID,
                cornerVertex: cornerVertex,
                in: session.document
            )
        )
        #expect(componentID.isStableTopology)
        let target = SelectionTarget(sceneNodeID: sceneNodeID, component: .vertex(componentID))
        let resolvedVertex = try resolver.cornerVertex(for: target, in: session.document)
        #expect(resolvedVertex == cornerVertex)
    }
}

@MainActor
@Test func generatedTopologySelectionResolverRejectsFixedTargets() async throws {
    let session = EditorSession()
    _ = try #require(session.createDefaultExtrudedRectangle())
    let bodyFeatureID = try #require(session.document.cadDocument.designGraph.order.last)
    let sceneNodeID = try #require(resolverSceneNodeID(for: bodyFeatureID, in: session.document))
    let faceTarget = SelectionTarget(sceneNodeID: sceneNodeID, component: .face(.bodyFaceTop))
    let edgeTarget = SelectionTarget(sceneNodeID: sceneNodeID, component: .edge(.bodyEdgeRightTop))
    let vertexTarget = SelectionTarget(
        sceneNodeID: sceneNodeID,
        component: .vertex(SelectionComponentID(rawValue: "body.vertex.frontTopRight"))
    )

    do {
        _ = try GeneratedTopologySelectionResolver().bodyFace(for: faceTarget, in: session.document)
        Issue.record("Fixed face targets must not be treated as generated topology references.")
    } catch let error as EditorError {
        #expect(error.code == .commandInvalid)
    }

    do {
        _ = try GeneratedTopologySelectionResolver().cornerEdge(for: edgeTarget, in: session.document)
        Issue.record("Fixed edge targets must not be treated as generated topology references.")
    } catch let error as EditorError {
        #expect(error.code == .commandInvalid)
    }

    do {
        _ = try GeneratedTopologySelectionResolver().cornerVertex(for: vertexTarget, in: session.document)
        Issue.record("Fixed vertex targets must not be treated as generated topology references.")
    } catch let error as EditorError {
        #expect(error.code == .commandInvalid)
    }
}

@MainActor
@Test func generatedTopologySelectionResolverResolvesCylinderDepthAndSideFaces() async throws {
    let session = EditorSession()
    _ = try #require(session.createDefaultExtrudedCircle())
    let bodyFeatureID = try #require(session.document.cadDocument.designGraph.order.last)
    let sceneNodeID = try #require(resolverSceneNodeID(for: bodyFeatureID, in: session.document))
    let resolver = GeneratedTopologySelectionResolver()

    let frontComponentID = try #require(
        try resolver.componentID(
            for: sceneNodeID,
            bodyFace: .front,
            in: session.document
        )
    )
    let backComponentID = try #require(
        try resolver.componentID(
            for: sceneNodeID,
            bodyFace: .back,
            in: session.document
        )
    )
    let sideComponentID = try #require(
        try resolver.componentID(
            for: sceneNodeID,
            bodyFace: .side,
            in: session.document
        )
    )

    #expect(frontComponentID.isStableTopology)
    #expect(backComponentID.isStableTopology)
    #expect(sideComponentID.isStableTopology)
    #expect(
        try resolver.bodyFace(
            for: SelectionTarget(sceneNodeID: sceneNodeID, component: .face(frontComponentID)),
            in: session.document
        ) == .front
    )
    #expect(
        try resolver.bodyFace(
            for: SelectionTarget(sceneNodeID: sceneNodeID, component: .face(backComponentID)),
            in: session.document
        ) == .back
    )
    #expect(
        try resolver.bodyFace(
            for: SelectionTarget(sceneNodeID: sceneNodeID, component: .face(sideComponentID)),
            in: session.document
        ) == .side
    )
}

private func resolverSceneNodeID(
    for featureID: FeatureID,
    in document: DesignDocument
) -> SceneNodeID? {
    document.productMetadata.sceneNodes.first { _, node in
        node.reference == .body(featureID)
    }?.key
}

private extension BodyFace {
    static var allCasesForTesting: [BodyFace] {
        [.front, .back, .top, .bottom, .left, .right]
    }
}

private extension BodyCornerEdge {
    static var allCasesForTesting: [BodyCornerEdge] {
        [.leftBottom, .rightBottom, .rightTop, .leftTop]
    }
}
