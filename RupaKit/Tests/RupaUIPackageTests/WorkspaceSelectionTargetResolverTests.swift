import RupaCore
import RupaRendering
import SwiftCAD
import Testing
@testable import RupaUI

@MainActor
@Test func workspaceSelectionTargetResolverResolvesGeneratedBodyTopology() throws {
    let session = EditorSession()
    _ = try #require(session.createDefaultExtrudedRectangle())
    let bodyFeatureID = try #require(session.document.cadDocument.designGraph.order.last)
    let sceneNodeID = try #require(
        sceneNodeID(
            for: bodyFeatureID,
            kind: .body,
            in: session.document
        )
    )
    let sceneRows = sceneRows(from: session.document)

    let faceTarget = try #require(
        resolver(
            document: session.document,
            sceneRows: sceneRows,
            scope: .face
        ).selectionTarget(for: ViewportHit(
            featureID: bodyFeatureID,
            kind: .body,
            bodyFace: .top
        ))
    )
    let edgeTarget = try #require(
        resolver(
            document: session.document,
            sceneRows: sceneRows,
            scope: .edge
        ).selectionTarget(for: ViewportHit(
            featureID: bodyFeatureID,
            kind: .body,
            bodyEdge: .rightTop
        ))
    )
    let vertexTarget = try #require(
        resolver(
            document: session.document,
            sceneRows: sceneRows,
            scope: .vertex
        ).selectionTarget(for: ViewportHit(
            featureID: bodyFeatureID,
            kind: .body,
            bodyVertex: .frontTopRight
        ))
    )

    #expect(faceTarget.sceneNodeID == sceneNodeID)
    #expect(edgeTarget.sceneNodeID == sceneNodeID)
    #expect(vertexTarget.sceneNodeID == sceneNodeID)
    guard case .face(let faceComponentID) = faceTarget.component else {
        Issue.record("Expected a face component.")
        return
    }
    guard case .edge(let edgeComponentID) = edgeTarget.component else {
        Issue.record("Expected an edge component.")
        return
    }
    guard case .vertex(let vertexComponentID) = vertexTarget.component else {
        Issue.record("Expected a vertex component.")
        return
    }
    #expect(faceComponentID.generatedTopologyPersistentName != nil)
    #expect(edgeComponentID.generatedTopologyPersistentName != nil)
    #expect(vertexComponentID.generatedTopologyPersistentName != nil)
}

@Test func workspaceSelectionTargetResolverDeduplicatesObjectTargetsThroughSceneRows() {
    let featureID = FeatureID()
    let bodyNode = SceneNode(
        name: "Body",
        reference: .body(featureID)
    )
    let sketchNode = SceneNode(
        name: "Sketch",
        reference: .sketch(featureID)
    )
    let document = document(
        sceneNodes: [
            bodyNode.id: bodyNode,
            sketchNode.id: sketchNode,
        ],
        rootSceneNodeIDs: [sketchNode.id, bodyNode.id]
    )
    let resolver = resolver(
        document: document,
        sceneRows: [
            SceneBrowserRow(id: sketchNode.id, depth: 0),
            SceneBrowserRow(id: bodyNode.id, depth: 0),
        ],
        scope: .object
    )
    let hits = [
        ViewportHit(featureID: featureID, kind: .body),
        ViewportHit(featureID: featureID, kind: .body),
    ]

    #expect(resolver.sceneNodeID(for: hits[0]) == bodyNode.id)
    #expect(resolver.selectionTargets(for: hits) == [
        SelectionTarget(sceneNodeID: bodyNode.id),
    ])
}

@Test func workspaceSelectionTargetResolverPrioritizesSketchPointTargets() {
    let featureID = FeatureID()
    let sceneNode = SceneNode(
        name: "Sketch",
        reference: .sketch(featureID)
    )
    let entityID = SketchEntityID()
    let document = document(
        sceneNodes: [sceneNode.id: sceneNode],
        rootSceneNodeIDs: [sceneNode.id]
    )
    let resolver = resolver(
        document: document,
        sceneRows: [SceneBrowserRow(id: sceneNode.id, depth: 0)],
        scope: .sketchEntity
    )
    let wholeCurveHit = ViewportHit(
        featureID: featureID,
        kind: .sketch,
        sketchEntityID: entityID
    )
    let pointHit = ViewportHit(
        featureID: featureID,
        kind: .sketch,
        sketchEntityID: entityID,
        sketchPointHandle: .lineStart
    )
    let pointTarget = SelectionTarget(
        sceneNodeID: sceneNode.id,
        component: .sketchEntity(
            .sketchPointHandle(
                featureID: featureID,
                entityID: entityID,
                handle: .lineStart
            )
        )
    )

    #expect(resolver.selectionTargets(for: [wholeCurveHit, pointHit, pointHit]) == [pointTarget])
}

private func resolver(
    document: DesignDocument,
    sceneRows: [SceneBrowserRow],
    scope: WorkspaceSelectionScope
) -> WorkspaceSelectionTargetResolver {
    WorkspaceSelectionTargetResolver(
        document: document,
        sceneBrowserRows: sceneRows,
        selectionScope: scope,
        objectRegistry: .builtIn
    )
}

private func document(
    sceneNodes: [SceneNodeID: SceneNode],
    rootSceneNodeIDs: [SceneNodeID]
) -> DesignDocument {
    var document = DesignDocument.empty()
    document.productMetadata = ProductMetadata(
        sceneNodes: sceneNodes,
        rootSceneNodeIDs: rootSceneNodeIDs
    )
    return document
}

private func sceneRows(from document: DesignDocument) -> [SceneBrowserRow] {
    var rows: [SceneBrowserRow] = []
    let metadata = document.productMetadata

    func append(_ id: SceneNodeID, depth: Int) {
        guard let node = metadata.sceneNodes[id] else {
            return
        }
        rows.append(SceneBrowserRow(id: id, depth: depth))
        for childID in node.childIDs {
            append(childID, depth: depth + 1)
        }
    }

    for rootSceneNodeID in metadata.rootSceneNodeIDs {
        append(rootSceneNodeID, depth: 0)
    }
    return rows
}

private func sceneNodeID(
    for featureID: FeatureID,
    kind: SceneNodeReference.Kind,
    in document: DesignDocument
) -> SceneNodeID? {
    document.productMetadata.sceneNodes.first { _, node in
        node.reference?.kind == kind && node.reference?.featureID == featureID
    }?.key
}
