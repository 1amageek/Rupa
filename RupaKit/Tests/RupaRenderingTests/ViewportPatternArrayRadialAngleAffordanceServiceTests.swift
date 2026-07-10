import CoreGraphics
import RupaCore
import SwiftCAD
import Testing
@testable import RupaRendering

@MainActor
@Test func patternArrayRadialAngleAffordanceServiceResolvesSourceSelectionAndDragAngle() async throws {
    let session = EditorSession()
    _ = try createDefaultRadialPatternSourceDefinition(
        in: session,
        definitionName: "Radial Angle Source"
    )
    let definition = try #require(session.document.productMetadata.componentDefinitions.values.first {
        $0.name == "Radial Angle Source"
    })
    _ = try session.execute(
        .createPatternArray(
            name: "Radial Angle Pattern",
            definitionID: definition.id,
            distribution: .radial(RadialPatternArray(
                angularAxis: PatternArrayAngularAxis(
                    center: .origin,
                    axis: .unitZ,
                    angle: .angle(90.0, .degree),
                    copyCount: 3,
                    angleMode: .extent
                )
            )),
            outputMode: .componentInstance
        )
    )
    let source = try #require(session.document.productMetadata.patternArrays.values.first {
        $0.name == "Radial Angle Pattern"
    })
    let scene = ViewportSceneBuilder().build(document: session.document, ruler: session.workspaceState.ruler)
    let layout = try #require(ViewportLayout(
        scene: scene,
        size: CGSize(width: 900.0, height: 700.0)
    ))

    let candidates = ViewportPatternArrayRadialAngleAffordanceService().candidates(
        document: session.document,
        scene: scene,
        selection: SelectionModel(selectedTargets: [
            SelectionTarget(sceneNodeID: source.rootSceneNodeID),
        ]),
        layout: layout
    )

    let candidate = try #require(candidates.first)
    let start = candidate.geometry.projectedTip()
    let targetAngle = Double.pi * 2.0 / 3.0
    let current = candidate.geometry.projectedTip(angleRadians: targetAngle)
    #expect(candidates.count == 1)
    #expect(candidate.target.sourceID == source.id)
    #expect(candidate.target.angleMode == .extent)
    #expect(abs(candidate.geometry.baseAngleRadians - Double.pi / 2.0) < 1.0e-12)
    #expect(abs(candidate.geometry.angleRadians(start: start, current: current) - targetAngle) < 1.0e-9)
}

@MainActor
@Test func radialAngleGeometryRestoresModelAngleFromProjectedEllipse() throws {
    let layout = ViewportLayout(
        modelBounds: CGRect(x: -0.2, y: -0.2, width: 0.4, height: 0.4),
        size: CGSize(width: 900.0, height: 700.0),
        basis: .orbit(yaw: 0.9, elevation: 0.42)
    )
    let geometry = try #require(ViewportPatternArrayRadialAngleAffordanceGeometry(
        center: .origin,
        axis: Vector3D(x: 0.2, y: 1.0, z: 0.25),
        referencePoint: Point3D(x: 0.08, y: 0.0, z: 0.0),
        angleRadians: Double.pi / 3.0,
        layout: layout
    ))
    let targetAngle = Double.pi * 0.72

    let restoredAngle = geometry.angleRadians(
        start: geometry.projectedTip(),
        current: geometry.projectedTip(angleRadians: targetAngle)
    )

    #expect(abs(restoredAngle - targetAngle) < 1.0e-9)
}

@MainActor
@Test func patternArrayRadialAngleAffordanceServiceResolvesReferencedAngle() async throws {
    let session = EditorSession()
    _ = try createDefaultRadialPatternSourceDefinition(
        in: session,
        definitionName: "Referenced Radial Angle Source"
    )
    _ = try session.execute(
        .upsertParameter(
            name: "radialAngle",
            expression: .constant(.angle(60.0, unit: .degree)),
            kind: .angle
        )
    )
    let angle = try #require(session.document.cadDocument.parameters.parameters.values.first {
        $0.name == "radialAngle"
    })
    let definition = try #require(session.document.productMetadata.componentDefinitions.values.first {
        $0.name == "Referenced Radial Angle Source"
    })
    _ = try session.execute(
        .createPatternArray(
            name: "Referenced Radial Angle Pattern",
            definitionID: definition.id,
            distribution: .radial(RadialPatternArray(
                angularAxis: PatternArrayAngularAxis(
                    center: .origin,
                    axis: .unitZ,
                    angle: .reference(angle.id),
                    copyCount: 3
                )
            )),
            outputMode: .componentInstance
        )
    )
    let source = try #require(session.document.productMetadata.patternArrays.values.first {
        $0.name == "Referenced Radial Angle Pattern"
    })
    let scene = ViewportSceneBuilder().build(document: session.document, ruler: session.workspaceState.ruler)
    let layout = try #require(ViewportLayout(
        scene: scene,
        size: CGSize(width: 900.0, height: 700.0)
    ))

    let candidates = ViewportPatternArrayRadialAngleAffordanceService().candidates(
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
    #expect(abs(candidate.geometry.baseAngleRadians - Double.pi / 3.0) < 1.0e-12)
}

@MainActor
@Test func patternArrayRadialAngleAffordanceServiceResolvesOutputSelection() async throws {
    let session = EditorSession()
    _ = try createDefaultRadialPatternSourceDefinition(
        in: session,
        definitionName: "Radial Output Angle Source"
    )
    let definition = try #require(session.document.productMetadata.componentDefinitions.values.first {
        $0.name == "Radial Output Angle Source"
    })
    _ = try session.execute(
        .createPatternArray(
            name: "Radial Output Angle Pattern",
            definitionID: definition.id,
            distribution: .radial(RadialPatternArray(
                angularAxis: PatternArrayAngularAxis(
                    center: .origin,
                    axis: .unitZ,
                    angle: .angle(45.0, .degree),
                    copyCount: 2
                )
            )),
            outputMode: .componentInstance
        )
    )
    let source = try #require(session.document.productMetadata.patternArrays.values.first {
        $0.name == "Radial Output Angle Pattern"
    })
    let outputSceneNodeID = try firstOutputSceneNodeID(source: source, document: session.document)
    let scene = ViewportSceneBuilder().build(document: session.document, ruler: session.workspaceState.ruler)
    let layout = try #require(ViewportLayout(
        scene: scene,
        size: CGSize(width: 900.0, height: 700.0)
    ))

    let candidates = ViewportPatternArrayRadialAngleAffordanceService().candidates(
        document: session.document,
        scene: scene,
        selection: SelectionModel(selectedTargets: [
            SelectionTarget(sceneNodeID: outputSceneNodeID),
        ]),
        layout: layout
    )

    let candidate = try #require(candidates.first)
    #expect(candidates.count == 1)
    #expect(candidate.target.sourceID == source.id)
    #expect(abs(candidate.geometry.baseAngleRadians - Double.pi / 4.0) < 1.0e-12)
}

@Test func patternArraySourceSelectionIndexPreservesBodyYMidpointForModelReference() throws {
    let definitionID = ComponentDefinitionID()
    let sourceSceneNodeID = SceneNodeID()
    let patternRootSceneNodeID = SceneNodeID()
    let sourceID = PatternArraySourceID()
    let source = PatternArraySource(
        id: sourceID,
        name: "Elevated Source",
        definitionID: definitionID,
        distribution: .radial(RadialPatternArray(
            angularAxis: PatternArrayAngularAxis(
                center: .origin,
                axis: .unitY,
                angle: .angle(45.0, .degree),
                copyCount: 2
            )
        )),
        outputMode: .componentInstance,
        outputInstanceIDs: [ComponentInstanceID()],
        rootSceneNodeID: patternRootSceneNodeID
    )
    let metadata = ProductMetadata(
        sceneNodes: [
            sourceSceneNodeID: SceneNode(id: sourceSceneNodeID, name: "Source Body"),
            patternRootSceneNodeID: SceneNode(id: patternRootSceneNodeID, name: "Pattern Root"),
        ],
        rootSceneNodeIDs: [sourceSceneNodeID, patternRootSceneNodeID],
        componentDefinitions: [
            definitionID: ComponentDefinition(
                id: definitionID,
                name: "Elevated Definition",
                rootSceneNodeIDs: [sourceSceneNodeID]
            ),
        ],
        patternArrays: [
            sourceID: source,
        ]
    )
    let scene = ViewportScene(items: [
        ViewportSceneItem(
            id: "source-body",
            featureID: FeatureID(),
            sceneNodeID: sourceSceneNodeID,
            modelBounds: CGRect(x: 1.0, y: 2.0, width: 4.0, height: 6.0),
            kind: .body(component: ViewportBodyComponent(
                sizeXMeters: 4.0,
                sizeYMeters: 8.0,
                sizeZMeters: 6.0,
                yMinMeters: 3.0,
                yMaxMeters: 11.0
            ))
        ),
    ])
    let index = ViewportPatternArraySourceSelectionIndex(
        metadata: metadata,
        scene: scene,
        selection: .empty
    )

    let point = try #require(index.sourceBaseModelPoint(source: source))

    #expect(point.x == 3.0)
    #expect(point.y == 7.0)
    #expect(point.z == 5.0)
}

@MainActor
@discardableResult
private func createDefaultRadialPatternSourceDefinition(
    in session: EditorSession,
    definitionName: String
) throws -> FeatureID {
    _ = try #require(session.createDefaultExtrudedRectangle())
    let bodyFeatureID = try #require(session.document.cadDocument.designGraph.order.last)
    let bodySceneNodeID = try sceneNodeID(for: bodyFeatureID, in: session.document)
    _ = try session.execute(
        .createComponentDefinition(
            name: definitionName,
            rootSceneNodeIDs: [bodySceneNodeID]
        )
    )
    return bodyFeatureID
}

private func firstOutputSceneNodeID(
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

private func sceneNodeID(
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
