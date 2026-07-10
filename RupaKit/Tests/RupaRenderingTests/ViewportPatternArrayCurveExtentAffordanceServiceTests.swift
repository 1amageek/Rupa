import CoreGraphics
import RupaCore
import SwiftCAD
import Testing
@testable import RupaRendering

@MainActor
@Test func patternArrayCurveExtentAffordanceServiceResolvesRatioExtentHandle() async throws {
    let session = EditorSession()
    _ = try createDefaultCurveExtentPatternSourceDefinition(
        in: session,
        definitionName: "Curve Ratio Source"
    )
    let definition = try #require(session.document.productMetadata.componentDefinitions.values.first {
        $0.name == "Curve Ratio Source"
    })
    _ = try session.execute(
        .createPatternArray(
            name: "Curve Ratio Pattern",
            definitionID: definition.id,
            distribution: .curve(CurvePatternArray(
                path: .polyline(
                    points: [
                        .origin,
                        Point3D(x: 0.1, y: 0.0, z: 0.0),
                    ],
                    normal: .unitZ
                ),
                copyCount: 3,
                extent: .scalar(0.5),
                extentMode: .ratio
            )),
            outputMode: .componentInstance
        )
    )
    let source = try #require(session.document.productMetadata.patternArrays.values.first {
        $0.name == "Curve Ratio Pattern"
    })
    let scene = ViewportSceneBuilder().build(document: session.document, ruler: session.workspaceState.ruler)
    let layout = try #require(ViewportLayout(scene: scene, size: CGSize(width: 900.0, height: 700.0)))

    let candidates = ViewportPatternArrayCurveExtentAffordanceService().candidates(
        document: session.document,
        scene: scene,
        selection: SelectionModel(selectedTargets: [
            SelectionTarget(sceneNodeID: source.rootSceneNodeID),
        ]),
        layout: layout
    )

    let candidate = try #require(candidates.first)
    let dragPoint = candidate.geometry.projectedTip(distanceMeters: 0.08)
    #expect(candidates.count == 1)
    #expect(candidate.target.sourceID == source.id)
    #expect(candidate.target.extentMode == .ratio)
    #expect(abs(candidate.geometry.totalLengthMeters - 0.1) < 1.0e-12)
    #expect(abs(candidate.geometry.baseDistanceMeters - 0.05) < 1.0e-12)
    #expect(abs(candidate.geometry.extentRatio(current: dragPoint) - 0.8) < 1.0e-9)
}

@MainActor
@Test func patternArrayCurveExtentAffordanceServiceResolvesOutputSelectionDistanceExtent() async throws {
    let session = EditorSession()
    _ = try createDefaultCurveExtentPatternSourceDefinition(
        in: session,
        definitionName: "Curve Distance Source"
    )
    let definition = try #require(session.document.productMetadata.componentDefinitions.values.first {
        $0.name == "Curve Distance Source"
    })
    _ = try session.execute(
        .createPatternArray(
            name: "Curve Distance Pattern",
            definitionID: definition.id,
            distribution: .curve(CurvePatternArray(
                path: .polyline(
                    points: [
                        .origin,
                        Point3D(x: 0.1, y: 0.0, z: 0.0),
                    ],
                    normal: .unitZ
                ),
                copyCount: 3,
                extent: .length(0.04, .meter),
                extentMode: .distance
            )),
            outputMode: .componentInstance
        )
    )
    let source = try #require(session.document.productMetadata.patternArrays.values.first {
        $0.name == "Curve Distance Pattern"
    })
    let outputSceneNodeID = try firstCurveExtentOutputSceneNodeID(source: source, document: session.document)
    let scene = ViewportSceneBuilder().build(document: session.document, ruler: session.workspaceState.ruler)
    let layout = try #require(ViewportLayout(scene: scene, size: CGSize(width: 900.0, height: 700.0)))

    let candidates = ViewportPatternArrayCurveExtentAffordanceService().candidates(
        document: session.document,
        scene: scene,
        selection: SelectionModel(selectedTargets: [
            SelectionTarget(sceneNodeID: outputSceneNodeID),
        ]),
        layout: layout
    )

    let candidate = try #require(candidates.first)
    let dragPoint = candidate.geometry.projectedTip(distanceMeters: 0.09)
    #expect(candidates.count == 1)
    #expect(candidate.target.sourceID == source.id)
    #expect(candidate.target.extentMode == .distance)
    #expect(abs(candidate.geometry.baseDistanceMeters - 0.04) < 1.0e-12)
    #expect(abs(candidate.geometry.extentDistance(current: dragPoint) - 0.09) < 1.0e-9)
}

@MainActor
@Test func patternArrayCurveExtentAffordanceServiceResolvesReferencedRatioExtent() async throws {
    let session = EditorSession()
    _ = try createDefaultCurveExtentPatternSourceDefinition(
        in: session,
        definitionName: "Referenced Curve Ratio Source"
    )
    _ = try session.execute(
        .upsertParameter(
            name: "curveExtentRatio",
            expression: .constant(.scalar(0.6)),
            kind: .scalar
        )
    )
    let ratio = try #require(session.document.cadDocument.parameters.parameters.values.first {
        $0.name == "curveExtentRatio"
    })
    let definition = try #require(session.document.productMetadata.componentDefinitions.values.first {
        $0.name == "Referenced Curve Ratio Source"
    })
    _ = try session.execute(
        .createPatternArray(
            name: "Referenced Curve Ratio Pattern",
            definitionID: definition.id,
            distribution: .curve(CurvePatternArray(
                path: .polyline(
                    points: [
                        .origin,
                        Point3D(x: 0.1, y: 0.0, z: 0.0),
                    ],
                    normal: .unitZ
                ),
                copyCount: 3,
                extent: .reference(ratio.id),
                extentMode: .ratio
            )),
            outputMode: .componentInstance
        )
    )
    let source = try #require(session.document.productMetadata.patternArrays.values.first {
        $0.name == "Referenced Curve Ratio Pattern"
    })
    let scene = ViewportSceneBuilder().build(document: session.document, ruler: session.workspaceState.ruler)
    let layout = try #require(ViewportLayout(scene: scene, size: CGSize(width: 900.0, height: 700.0)))

    let candidates = ViewportPatternArrayCurveExtentAffordanceService().candidates(
        document: session.document,
        scene: scene,
        selection: SelectionModel(selectedTargets: [
            SelectionTarget(sceneNodeID: source.rootSceneNodeID),
        ]),
        layout: layout
    )

    let candidate = try #require(candidates.first)
    #expect(candidates.count == 1)
    #expect(candidate.target.sourceID == source.id)
    #expect(candidate.target.extentMode == .ratio)
    #expect(abs(candidate.geometry.baseDistanceMeters - 0.06) < 1.0e-12)
}

@MainActor
@discardableResult
private func createDefaultCurveExtentPatternSourceDefinition(
    in session: EditorSession,
    definitionName: String
) throws -> FeatureID {
    _ = try #require(session.createDefaultExtrudedRectangle())
    let bodyFeatureID = try #require(session.document.cadDocument.designGraph.order.last)
    let bodySceneNodeID = try curveExtentSceneNodeID(for: bodyFeatureID, in: session.document)
    _ = try session.execute(
        .createComponentDefinition(
            name: definitionName,
            rootSceneNodeIDs: [bodySceneNodeID]
        )
    )
    return bodyFeatureID
}

private func firstCurveExtentOutputSceneNodeID(
    source: PatternArraySource,
    document: DesignDocument
) throws -> SceneNodeID {
    let rootNode = try #require(document.productMetadata.sceneNodes[source.rootSceneNodeID])
    return try #require(rootNode.childIDs.first { childID in
        guard let componentInstanceID = document.productMetadata.sceneNodes[childID]?.reference?.componentInstanceID else {
            return false
        }
        return source.outputInstanceIDs.contains(componentInstanceID)
    })
}

private func curveExtentSceneNodeID(
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
