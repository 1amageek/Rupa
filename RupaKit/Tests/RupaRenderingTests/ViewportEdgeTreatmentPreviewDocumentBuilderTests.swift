import Foundation
import RupaCore
import SwiftCAD
import Testing
@testable import RupaRendering

@MainActor
@Test func viewportEdgeTreatmentPreviewBuilderCreatesChamferPreviewWithoutMutatingSource() throws {
    let session = EditorSession()
    _ = try #require(session.createDefaultExtrudedRectangle())
    let bodyFeatureID = try #require(session.document.cadDocument.designGraph.order.last)
    let bodyNodeID = try #require(previewBodySceneNodeID(for: bodyFeatureID, in: session.document))
    let target = SelectionTarget(sceneNodeID: bodyNodeID, component: .edge(.bodyEdgeRightTop))

    let preview = try ViewportEdgeTreatmentPreviewDocumentBuilder().previewDocument(
        for: .chamfer(target: target, distance: 0.001),
        in: session.document
    )

    #expect(try previewProfileEntityCounts(forBody: bodyFeatureID, in: session.document).lines == 4)
    #expect(try previewProfileEntityCounts(forBody: bodyFeatureID, in: session.document).arcs == 0)
    #expect(try previewProfileEntityCounts(forBody: bodyFeatureID, in: preview).lines == 5)
    #expect(try previewProfileEntityCounts(forBody: bodyFeatureID, in: preview).arcs == 0)
}

@MainActor
@Test func viewportEdgeTreatmentPreviewBuilderCreatesFilletPreviewWithoutMutatingSource() throws {
    let session = EditorSession()
    _ = try #require(session.createDefaultExtrudedRectangle())
    let bodyFeatureID = try #require(session.document.cadDocument.designGraph.order.last)
    let bodyNodeID = try #require(previewBodySceneNodeID(for: bodyFeatureID, in: session.document))
    let target = SelectionTarget(sceneNodeID: bodyNodeID, component: .edge(.bodyEdgeRightTop))

    let preview = try ViewportEdgeTreatmentPreviewDocumentBuilder().previewDocument(
        for: .fillet(target: target, radius: 0.001, segmentCount: 8),
        in: session.document
    )

    #expect(try previewProfileEntityCounts(forBody: bodyFeatureID, in: session.document).lines == 4)
    #expect(try previewProfileEntityCounts(forBody: bodyFeatureID, in: session.document).arcs == 0)
    #expect(try previewProfileEntityCounts(forBody: bodyFeatureID, in: preview).arcs == 1)
}

private func previewBodySceneNodeID(
    for featureID: FeatureID,
    in document: DesignDocument
) -> SceneNodeID? {
    document.productMetadata.sceneNodes.first { entry in
        entry.value.reference?.kind == .body && entry.value.reference?.featureID == featureID
    }?.key
}

private func previewProfileEntityCounts(
    forBody featureID: FeatureID,
    in document: DesignDocument
) throws -> (lines: Int, arcs: Int) {
    let feature = try #require(document.cadDocument.designGraph.nodes[featureID])
    guard case .extrude(let extrude) = feature.operation else {
        Issue.record("Preview edge treatment test requires an extrude body.")
        return (0, 0)
    }
    let profileFeature = try #require(document.cadDocument.designGraph.nodes[extrude.profile.featureID])
    guard case .sketch(let sketch) = profileFeature.operation else {
        Issue.record("Preview edge treatment test requires a sketch profile.")
        return (0, 0)
    }
    var lineCount = 0
    var arcCount = 0
    for entity in sketch.entities.values {
        switch entity {
        case .line:
            lineCount += 1
        case .arc:
            arcCount += 1
        default:
            break
        }
    }
    return (lineCount, arcCount)
}
