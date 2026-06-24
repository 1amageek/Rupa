import CoreGraphics
import RupaCore
import SwiftCAD
import Testing
@testable import RupaRendering

@MainActor
@Test func patternArrayCurvePathReplacementPreviewServiceProjectsCandidateCurveOutputsWithoutMutatingSource() async throws {
    let session = EditorSession()
    _ = try createCurvePathReplacementPreviewSourceDefinition(
        in: session,
        definitionName: "Curve Preview Source"
    )
    let definition = try #require(session.document.productMetadata.componentDefinitions.values.first {
        $0.name == "Curve Preview Source"
    })
    let originalPath = PatternArrayCurvePath.polyline(
        points: [
            .origin,
            Point3D(x: 0.1, y: 0.0, z: 0.0),
        ],
        normal: .unitZ
    )
    _ = try session.execute(
        .createPatternArray(
            name: "Curve Preview Pattern",
            definitionID: definition.id,
            distribution: .curve(CurvePatternArray(
                path: originalPath,
                copyCount: 3,
                extent: .scalar(1.0),
                extentMode: .ratio
            )),
            outputMode: .componentInstance
        )
    )
    let source = try #require(session.document.productMetadata.patternArrays.values.first {
        $0.name == "Curve Preview Pattern"
    })
    let replacementPath = PatternArrayCurvePath.polyline(
        points: [
            .origin,
            Point3D(x: 0.0, y: 0.0, z: 0.12),
        ],
        normal: .unitY
    )
    let scene = ViewportSceneBuilder().build(document: session.document)
    let layout = try #require(ViewportLayout(scene: scene, size: CGSize(width: 900.0, height: 700.0)))

    let preview = try #require(ViewportPatternArrayCurvePathReplacementPreviewService().preview(
        document: session.document,
        scene: scene,
        layout: layout,
        request: ViewportPatternArrayCurvePathReplacementPreviewRequest(
            sourceID: source.id,
            path: replacementPath,
            title: "Candidate Path"
        )
    ))

    let unchangedSource = try #require(session.document.productMetadata.patternArrays[source.id])
    guard case .curve(let unchangedCurve) = unchangedSource.distribution else {
        Issue.record("Expected source to remain a Curve Pattern Array.")
        return
    }
    #expect(unchangedCurve.path == originalPath)
    #expect(preview.sourceID == source.id)
    #expect(preview.title == "Candidate Path")
    #expect(preview.outputPoints.count == 3)
    #expect(preview.totalOutputCount == 3)
    #expect(preview.pathPoints.count == 73)
    #expect(preview.outputPoints.allSatisfy { point in
        point.x.isFinite && point.y.isFinite
    })
}

@MainActor
@Test func patternArrayCurvePathReplacementPreviewServiceIgnoresNonCurveSources() async throws {
    let session = EditorSession()
    _ = try createCurvePathReplacementPreviewSourceDefinition(
        in: session,
        definitionName: "Rectangular Preview Source"
    )
    let definition = try #require(session.document.productMetadata.componentDefinitions.values.first {
        $0.name == "Rectangular Preview Source"
    })
    _ = try session.execute(
        .createPatternArray(
            name: "Rectangular Preview Pattern",
            definitionID: definition.id,
            distribution: .rectangular(RectangularPatternArray(
                firstAxis: PatternArrayLinearAxis(
                    direction: .unitX,
                    distance: .length(0.03, .meter),
                    copyCount: 2
                )
            )),
            outputMode: .componentInstance
        )
    )
    let source = try #require(session.document.productMetadata.patternArrays.values.first {
        $0.name == "Rectangular Preview Pattern"
    })
    let scene = ViewportSceneBuilder().build(document: session.document)
    let layout = try #require(ViewportLayout(scene: scene, size: CGSize(width: 900.0, height: 700.0)))

    let preview = ViewportPatternArrayCurvePathReplacementPreviewService().preview(
        document: session.document,
        scene: scene,
        layout: layout,
        request: ViewportPatternArrayCurvePathReplacementPreviewRequest(
            sourceID: source.id,
            path: .polyline(
                points: [
                    .origin,
                    Point3D(x: 0.0, y: 0.0, z: 0.12),
                ],
                normal: .unitY
            ),
            title: "Candidate Path"
        )
    )

    #expect(preview == nil)
}

@MainActor
@discardableResult
private func createCurvePathReplacementPreviewSourceDefinition(
    in session: EditorSession,
    definitionName: String
) throws -> FeatureID {
    _ = try #require(session.createDefaultExtrudedRectangle())
    let bodyFeatureID = try #require(session.document.cadDocument.designGraph.order.last)
    let bodySceneNodeID = try curvePathReplacementPreviewSceneNodeID(
        for: bodyFeatureID,
        in: session.document
    )
    _ = try session.execute(
        .createComponentDefinition(
            name: definitionName,
            rootSceneNodeIDs: [bodySceneNodeID]
        )
    )
    return bodyFeatureID
}

private func curvePathReplacementPreviewSceneNodeID(
    for featureID: FeatureID,
    in document: DesignDocument
) throws -> SceneNodeID {
    guard let sceneNode = document.productMetadata.sceneNodes.first(where: { _, node in
        node.reference?.featureID == featureID
    }) else {
        throw EditorError(
            code: .referenceUnresolved,
            message: "Expected a scene node for the feature."
        )
    }
    return sceneNode.key
}
