import CoreGraphics
import RupaCore
import SwiftCAD
import Testing
@testable import RupaRendering

@MainActor
@Test func patternArrayCurvePathPointAffordanceServiceResolvesPolylinePointHandles() async throws {
    let session = EditorSession()
    _ = try createCurvePathPointPatternSourceDefinition(
        in: session,
        definitionName: "Curve Point Source"
    )
    let definition = try #require(session.document.productMetadata.componentDefinitions.values.first {
        $0.name == "Curve Point Source"
    })
    let points = [
        Point3D.origin,
        Point3D(x: 0.03, y: 0.0, z: 0.02),
        Point3D(x: 0.06, y: 0.0, z: 0.0),
    ]
    _ = try session.execute(
        .createPatternArray(
            name: "Curve Point Pattern",
            definitionID: definition.id,
            distribution: .curve(CurvePatternArray(
                path: .polyline(points: points, normal: .unitZ),
                copyCount: 2
            )),
            outputMode: .componentInstance
        )
    )
    let source = try #require(session.document.productMetadata.patternArrays.values.first {
        $0.name == "Curve Point Pattern"
    })
    let scene = ViewportSceneBuilder().build(document: session.document, ruler: session.workspaceState.ruler)
    let layout = try #require(ViewportLayout(scene: scene, size: CGSize(width: 900.0, height: 700.0)))

    let candidates = ViewportPatternArrayCurvePathPointAffordanceService().candidates(
        document: session.document,
        scene: scene,
        selection: SelectionModel(selectedTargets: [
            SelectionTarget(sceneNodeID: source.rootSceneNodeID),
        ]),
        layout: layout
    )

    #expect(candidates.map(\.target.pointIndex) == [0, 1, 2])
    #expect(candidates.map(\.target.basePoint) == points)
    #expect(candidates.allSatisfy { $0.target.sourceID == source.id })
    #expect(candidates.allSatisfy { $0.projectedPathPoints.count == points.count })
}

@MainActor
@Test func patternArrayCurvePathPointAffordanceServiceResolvesOutputSelection() async throws {
    let session = EditorSession()
    _ = try createCurvePathPointPatternSourceDefinition(
        in: session,
        definitionName: "Curve Point Output Source"
    )
    let definition = try #require(session.document.productMetadata.componentDefinitions.values.first {
        $0.name == "Curve Point Output Source"
    })
    _ = try session.execute(
        .createPatternArray(
            name: "Curve Point Output Pattern",
            definitionID: definition.id,
            distribution: .curve(CurvePatternArray(
                path: .polyline(
                    points: [
                        .origin,
                        Point3D(x: 0.03, y: 0.0, z: 0.02),
                    ],
                    normal: .unitZ
                ),
                copyCount: 2
            )),
            outputMode: .componentInstance
        )
    )
    let source = try #require(session.document.productMetadata.patternArrays.values.first {
        $0.name == "Curve Point Output Pattern"
    })
    let outputSceneNodeID = try firstCurvePathPointOutputSceneNodeID(
        source: source,
        document: session.document
    )
    let scene = ViewportSceneBuilder().build(document: session.document, ruler: session.workspaceState.ruler)
    let layout = try #require(ViewportLayout(scene: scene, size: CGSize(width: 900.0, height: 700.0)))

    let candidates = ViewportPatternArrayCurvePathPointAffordanceService().candidates(
        document: session.document,
        scene: scene,
        selection: SelectionModel(selectedTargets: [
            SelectionTarget(sceneNodeID: outputSceneNodeID),
        ]),
        layout: layout
    )

    #expect(candidates.map(\.target.pointIndex) == [0, 1])
    #expect(candidates.allSatisfy { $0.target.sourceID == source.id })
}

@MainActor
@Test func patternArrayCurvePathPointAffordanceServiceIgnoresSketchEntityPaths() async throws {
    let session = EditorSession()
    _ = try #require(session.createDefaultExtrudedRectangle())
    let pathReference = try firstCurvePathPointSketchCurveReference(in: session.document)
    let bodyFeatureID = try #require(session.document.cadDocument.designGraph.order.last)
    let bodySceneNodeID = try curvePathPointSceneNodeID(for: bodyFeatureID, in: session.document)
    _ = try session.execute(
        .createComponentDefinition(
            name: "Sketch Entity Curve Point Source",
            rootSceneNodeIDs: [bodySceneNodeID]
        )
    )
    let definition = try #require(session.document.productMetadata.componentDefinitions.values.first {
        $0.name == "Sketch Entity Curve Point Source"
    })
    _ = try session.execute(
        .createPatternArray(
            name: "Sketch Entity Curve Point Pattern",
            definitionID: definition.id,
            distribution: .curve(CurvePatternArray(
                path: .sketchEntity(
                    featureID: pathReference.featureID,
                    entityID: pathReference.entityID
                ),
                copyCount: 2
            )),
            outputMode: .componentInstance
        )
    )
    let source = try #require(session.document.productMetadata.patternArrays.values.first {
        $0.name == "Sketch Entity Curve Point Pattern"
    })
    let scene = ViewportSceneBuilder().build(document: session.document, ruler: session.workspaceState.ruler)
    let layout = try #require(ViewportLayout(scene: scene, size: CGSize(width: 900.0, height: 700.0)))

    let candidates = ViewportPatternArrayCurvePathPointAffordanceService().candidates(
        document: session.document,
        scene: scene,
        selection: SelectionModel(selectedTargets: [
            SelectionTarget(sceneNodeID: source.rootSceneNodeID),
        ]),
        layout: layout
    )

    #expect(candidates.isEmpty)
}

@MainActor
@discardableResult
private func createCurvePathPointPatternSourceDefinition(
    in session: EditorSession,
    definitionName: String
) throws -> FeatureID {
    _ = try #require(session.createDefaultExtrudedRectangle())
    let bodyFeatureID = try #require(session.document.cadDocument.designGraph.order.last)
    let bodySceneNodeID = try curvePathPointSceneNodeID(for: bodyFeatureID, in: session.document)
    _ = try session.execute(
        .createComponentDefinition(
            name: definitionName,
            rootSceneNodeIDs: [bodySceneNodeID]
        )
    )
    return bodyFeatureID
}

private func firstCurvePathPointOutputSceneNodeID(
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

private func firstCurvePathPointSketchCurveReference(
    in document: DesignDocument
) throws -> (featureID: FeatureID, entityID: SketchEntityID) {
    for featureID in document.cadDocument.designGraph.order {
        guard let node = document.cadDocument.designGraph.nodes[featureID],
              case .sketch(let sketch) = node.operation else {
            continue
        }
        for (entityID, entity) in sketch.entities {
            switch entity {
            case .line, .circle, .arc, .spline:
                return (featureID, entityID)
            case .point:
                continue
            }
        }
    }
    throw EditorError(
        code: .referenceUnresolved,
        message: "Expected a sketch curve entity."
    )
}

private func curvePathPointSceneNodeID(
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
