import CoreGraphics
import RupaCore
import SwiftCAD
import Testing
@testable import RupaRendering

@MainActor
@Test func independentCopyExtrudeDistanceAffordanceResolvesSelectedOutputRoot() async throws {
    let session = EditorSession()
    let source = try createIndependentCopyPatternArray(
        in: session,
        definitionName: "Extrude Distance Root Source",
        arrayName: "Extrude Distance Root Array"
    )
    let firstOutputSceneNodeID = try #require(source.outputSceneNodeIDs.first)
    let scene = ViewportSceneBuilder().build(document: session.document, ruler: session.workspaceState.ruler)
    let layout = try #require(ViewportLayout(
        scene: scene,
        size: CGSize(width: 900.0, height: 700.0)
    ))

    let candidates = ViewportIndependentCopyExtrudeDistanceAffordanceService().candidates(
        document: session.document,
        scene: scene,
        selection: SelectionModel(selectedTargets: [
            SelectionTarget(sceneNodeID: firstOutputSceneNodeID),
        ]),
        layout: layout
    )

    let candidate = try #require(candidates.first)
    #expect(candidates.count == 1)
    #expect(candidate.target.sourceID == source.id)
    #expect(candidate.target.outputIndex == 0)
    #expect(candidate.target.outputSceneNodeID == firstOutputSceneNodeID)
    #expect(source.outputFeatureIDs.contains(candidate.target.featureID))
    #expect(candidate.geometry.baseDistanceMeters > 0.0)
}

@MainActor
@Test func independentCopyExtrudeDistanceAffordanceResolvesSelectedOutputDescendant() async throws {
    let session = EditorSession()
    let source = try createIndependentCopyPatternArray(
        in: session,
        definitionName: "Extrude Distance Descendant Source",
        arrayName: "Extrude Distance Descendant Array"
    )
    let firstOutputSceneNodeID = try #require(source.outputSceneNodeIDs.first)
    let scene = ViewportSceneBuilder().build(document: session.document, ruler: session.workspaceState.ruler)
    let descendantSceneNodeID = try renderableDescendantSceneNodeID(
        rootedAt: firstOutputSceneNodeID,
        scene: scene,
        document: session.document
    )
    let layout = try #require(ViewportLayout(
        scene: scene,
        size: CGSize(width: 900.0, height: 700.0)
    ))

    let candidates = ViewportIndependentCopyExtrudeDistanceAffordanceService().candidates(
        document: session.document,
        scene: scene,
        selection: SelectionModel(selectedTargets: [
            SelectionTarget(sceneNodeID: descendantSceneNodeID),
        ]),
        layout: layout
    )

    let candidate = try #require(candidates.first)
    #expect(candidates.count == 1)
    #expect(candidate.target.sourceID == source.id)
    #expect(candidate.target.outputIndex == 0)
    #expect(candidate.target.outputSceneNodeID == firstOutputSceneNodeID)
}

@MainActor
@Test func independentCopyExtrudeDistanceAffordanceUsesEditedCloneDistance() async throws {
    let session = EditorSession()
    let source = try createIndependentCopyPatternArray(
        in: session,
        definitionName: "Extrude Distance Edited Source",
        arrayName: "Extrude Distance Edited Array"
    )
    let firstOutputSceneNodeID = try #require(source.outputSceneNodeIDs.first)
    let firstCloneBodyFeatureID = try bodyFeatureID(
        inSceneSubtreeRootedAt: firstOutputSceneNodeID,
        document: session.document
    )
    _ = try session.execute(
        .setExtrudeDistance(
            featureID: firstCloneBodyFeatureID,
            distance: .length(7.0, .millimeter)
        )
    )
    let updatedSource = try #require(session.document.productMetadata.patternArrays[source.id])
    let scene = ViewportSceneBuilder().build(document: session.document, ruler: session.workspaceState.ruler)
    let layout = try #require(ViewportLayout(
        scene: scene,
        size: CGSize(width: 900.0, height: 700.0)
    ))

    let candidates = ViewportIndependentCopyExtrudeDistanceAffordanceService().candidates(
        document: session.document,
        scene: scene,
        selection: SelectionModel(selectedTargets: [
            SelectionTarget(sceneNodeID: firstOutputSceneNodeID),
        ]),
        layout: layout
    )

    let candidate = try #require(candidates.first)
    let start = candidate.geometry.projectedTip()
    let current = CGPoint(
        x: start.x + candidate.geometry.projectedDirection.dx * candidate.geometry.pointsPerMeter * 0.003,
        y: start.y + candidate.geometry.projectedDirection.dy * candidate.geometry.pointsPerMeter * 0.003
    )
    #expect(updatedSource.outputFeatureIDs.contains(firstCloneBodyFeatureID))
    #expect(candidate.target.featureID == firstCloneBodyFeatureID)
    #expect(abs(candidate.geometry.baseDistanceMeters - 0.007) < 1.0e-12)
    #expect(abs(candidate.geometry.axisDistance(start: start, current: current) - 0.010) < 1.0e-12)
}

@MainActor
@Test func independentCopyExtrudeDistanceAffordanceAppliesOutputScaleToDisplayedDistance() async throws {
    let session = EditorSession()
    let source = try createIndependentCopyPatternArray(
        in: session,
        definitionName: "Extrude Distance Scaled Source",
        arrayName: "Extrude Distance Scaled Array",
        distribution: .curve(CurvePatternArray(
            path: .polyline(
                points: [.origin, Point3D(x: 0.080, y: 0.0, z: 0.0)],
                normal: .unitZ
            ),
            copyCount: 1,
            endScale: .scalar(2.0),
            alignment: .parallel
        ))
    )
    let firstOutputSceneNodeID = try #require(source.outputSceneNodeIDs.first)
    let scene = ViewportSceneBuilder().build(document: session.document, ruler: session.workspaceState.ruler)
    let layout = try #require(ViewportLayout(
        scene: scene,
        size: CGSize(width: 900.0, height: 700.0)
    ))

    let candidates = ViewportIndependentCopyExtrudeDistanceAffordanceService().candidates(
        document: session.document,
        scene: scene,
        selection: SelectionModel(selectedTargets: [
            SelectionTarget(sceneNodeID: firstOutputSceneNodeID),
        ]),
        layout: layout
    )

    let candidate = try #require(candidates.first)
    #expect(abs(candidate.target.valueScale - 2.0) < 1.0e-12)
    #expect(abs(candidate.geometry.baseDistanceMeters - 0.020) < 1.0e-12)
}

@MainActor
@Test func independentCopyExtrudeDistanceAffordanceUsesSceneTransformedBodyCenterAsBasePoint() async throws {
    let session = EditorSession()
    let source = try createIndependentCopyPatternArray(
        in: session,
        definitionName: "Extrude Distance Base Point Source",
        arrayName: "Extrude Distance Base Point Array",
        distribution: .rectangular(RectangularPatternArray(
            firstAxis: PatternArrayLinearAxis(
                direction: .unitX,
                distance: .length(100.0, .millimeter),
                copyCount: 1
            )
        ))
    )
    let firstOutputSceneNodeID = try #require(source.outputSceneNodeIDs.first)
    let scene = ViewportSceneBuilder().build(document: session.document, ruler: session.workspaceState.ruler)
    let outputBodyItem = try bodyItem(
        rootedAt: firstOutputSceneNodeID,
        source: source,
        scene: scene,
        document: session.document
    )
    let layout = try #require(ViewportLayout(
        scene: scene,
        size: CGSize(width: 900.0, height: 700.0)
    ))

    let candidates = ViewportIndependentCopyExtrudeDistanceAffordanceService().candidates(
        document: session.document,
        scene: scene,
        selection: SelectionModel(selectedTargets: [
            SelectionTarget(sceneNodeID: firstOutputSceneNodeID),
        ]),
        layout: layout
    )

    let candidate = try #require(candidates.first)
    let expectedBasePoint = layout.project(Point3D(
        x: Double(outputBodyItem.modelBounds.midX),
        y: bodyCenterY(for: outputBodyItem),
        z: Double(outputBodyItem.modelBounds.midY)
    ))
    #expect(abs(candidate.geometry.baseProjectedPoint.x - expectedBasePoint.x) < 1.0e-9)
    #expect(abs(candidate.geometry.baseProjectedPoint.y - expectedBasePoint.y) < 1.0e-9)
}

@MainActor
@Test func independentCopyExtrudeDistanceAffordanceAppliesOutputRotationToHandleAxis() async throws {
    let session = EditorSession()
    let source = try createIndependentCopyPatternArray(
        in: session,
        definitionName: "Extrude Distance Rotated Source",
        arrayName: "Extrude Distance Rotated Array",
        distribution: .radial(RadialPatternArray(
            angularAxis: PatternArrayAngularAxis(
                center: .origin,
                axis: .unitY,
                angle: .angle(90.0, .degree),
                copyCount: 1
            )
        ))
    )
    let firstOutputSceneNodeID = try #require(source.outputSceneNodeIDs.first)
    let outputTransform = try #require(session.document.productMetadata.sceneNodes[firstOutputSceneNodeID]?.localTransform)
    let scene = ViewportSceneBuilder().build(document: session.document, ruler: session.workspaceState.ruler)
    let layout = try #require(ViewportLayout(
        scene: scene,
        size: CGSize(width: 900.0, height: 700.0)
    ))

    let candidates = ViewportIndependentCopyExtrudeDistanceAffordanceService().candidates(
        document: session.document,
        scene: scene,
        selection: SelectionModel(selectedTargets: [
            SelectionTarget(sceneNodeID: firstOutputSceneNodeID),
        ]),
        layout: layout
    )

    let candidate = try #require(candidates.first)
    let expectedDirection = projectedDirection(
        for: outputTransform.viewportTransformedVector(.unitZ),
        layout: layout
    )
    #expect(abs(candidate.geometry.projectedDirection.dx - expectedDirection.dx) < 1.0e-12)
    #expect(abs(candidate.geometry.projectedDirection.dy - expectedDirection.dy) < 1.0e-12)
}

@MainActor
@Test func independentCopyExtrudeDistanceAffordanceUsesProfilePlaneNormal() async throws {
    let session = EditorSession()
    let planeResult = try #require(session.createConstructionPlane(
        name: "YZ Plane",
        plane: .yz
    ))
    let planeID = try #require(planeResult.createdConstructionPlaneID)
    _ = try #require(session.setActiveConstructionPlane(id: planeID))
    let source = try createIndependentCopyPatternArray(
        in: session,
        definitionName: "Extrude Distance YZ Source",
        arrayName: "Extrude Distance YZ Array"
    )
    let firstOutputSceneNodeID = try #require(source.outputSceneNodeIDs.first)
    let scene = ViewportSceneBuilder().build(document: session.document, ruler: session.workspaceState.ruler)
    let layout = try #require(ViewportLayout(
        scene: scene,
        size: CGSize(width: 900.0, height: 700.0)
    ))

    let candidates = ViewportIndependentCopyExtrudeDistanceAffordanceService().candidates(
        document: session.document,
        scene: scene,
        selection: SelectionModel(selectedTargets: [
            SelectionTarget(sceneNodeID: firstOutputSceneNodeID),
        ]),
        layout: layout
    )

    let candidate = try #require(candidates.first)
    let expectedDirection = projectedDirection(for: .unitX, layout: layout)
    #expect(abs(candidate.geometry.projectedDirection.dx - expectedDirection.dx) < 1.0e-12)
    #expect(abs(candidate.geometry.projectedDirection.dy - expectedDirection.dy) < 1.0e-12)
}

@MainActor
@Test func independentCopyExtrudeDistanceAffordanceReturnsAllOutputExtrudesWhenOutputRootSelected() async throws {
    let session = EditorSession()
    let source = try createIndependentCopyPatternArray(
        in: session,
        definitionName: "Extrude Distance Multi Body Source",
        arrayName: "Extrude Distance Multi Body Array",
        sourceBodyCount: 2
    )
    let firstOutputSceneNodeID = try #require(source.outputSceneNodeIDs.first)
    let scene = ViewportSceneBuilder().build(document: session.document, ruler: session.workspaceState.ruler)
    let layout = try #require(ViewportLayout(
        scene: scene,
        size: CGSize(width: 900.0, height: 700.0)
    ))

    let candidates = ViewportIndependentCopyExtrudeDistanceAffordanceService().candidates(
        document: session.document,
        scene: scene,
        selection: SelectionModel(selectedTargets: [
            SelectionTarget(sceneNodeID: firstOutputSceneNodeID),
        ]),
        layout: layout
    )

    #expect(candidates.count == 2)
    #expect(Set(candidates.map(\.target.featureID)).isSubset(of: Set(source.outputFeatureIDs)))
}

@MainActor
@Test func independentCopyExtrudeDistanceAffordanceRequiresSelectedIndependentCopyOutput() async throws {
    let session = EditorSession()
    let source = try createIndependentCopyPatternArray(
        in: session,
        definitionName: "Extrude Distance Source Root Source",
        arrayName: "Extrude Distance Source Root Array"
    )
    let scene = ViewportSceneBuilder().build(document: session.document, ruler: session.workspaceState.ruler)
    let layout = try #require(ViewportLayout(
        scene: scene,
        size: CGSize(width: 900.0, height: 700.0)
    ))

    let candidates = ViewportIndependentCopyExtrudeDistanceAffordanceService().candidates(
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
@Test func independentCopyExtrudeDistanceAffordanceIgnoresComponentInstanceOutputs() async throws {
    let session = EditorSession()
    _ = try createDefaultPatternSourceDefinition(
        in: session,
        definitionName: "Component Instance Extrude Source"
    )
    let definition = try #require(session.document.productMetadata.componentDefinitions.values.first {
        $0.name == "Component Instance Extrude Source"
    })
    _ = try session.execute(
        .createPatternArray(
            name: "Component Instance Extrude Array",
            definitionID: definition.id,
            distribution: .rectangular(RectangularPatternArray(
                firstAxis: PatternArrayLinearAxis(
                    direction: .unitX,
                    distance: .length(8.0, .millimeter),
                    copyCount: 2
                )
            )),
            outputMode: .componentInstance
        )
    )
    let source = try #require(session.document.productMetadata.patternArrays.values.first {
        $0.name == "Component Instance Extrude Array"
    })
    let outputSceneNodeID = try outputSceneNodeID(for: source, document: session.document)
    let scene = ViewportSceneBuilder().build(document: session.document, ruler: session.workspaceState.ruler)
    let layout = try #require(ViewportLayout(
        scene: scene,
        size: CGSize(width: 900.0, height: 700.0)
    ))

    let candidates = ViewportIndependentCopyExtrudeDistanceAffordanceService().candidates(
        document: session.document,
        scene: scene,
        selection: SelectionModel(selectedTargets: [
            SelectionTarget(sceneNodeID: outputSceneNodeID),
        ]),
        layout: layout
    )

    #expect(candidates.isEmpty)
}

@MainActor
private func createIndependentCopyPatternArray(
    in session: EditorSession,
    definitionName: String,
    arrayName: String,
    sourceBodyCount: Int = 1,
    distribution: PatternArrayDistribution? = nil
) throws -> PatternArraySource {
    _ = try createPatternSourceDefinition(
        in: session,
        definitionName: definitionName,
        bodyCount: sourceBodyCount
    )
    let definition = try #require(session.document.productMetadata.componentDefinitions.values.first {
        $0.name == definitionName
    })
    let resolvedDistribution = distribution ?? .rectangular(RectangularPatternArray(
        firstAxis: PatternArrayLinearAxis(
            direction: .unitX,
            distance: .length(8.0, .millimeter),
            copyCount: 2
        )
    ))
    _ = try session.execute(
        .createPatternArray(
            name: arrayName,
            definitionID: definition.id,
            distribution: resolvedDistribution,
            outputMode: .independentCopy
        )
    )
    return try #require(session.document.productMetadata.patternArrays.values.first {
        $0.name == arrayName
    })
}

@MainActor
@discardableResult
private func createDefaultPatternSourceDefinition(
    in session: EditorSession,
    definitionName: String
) throws -> FeatureID {
    let featureIDs = try createPatternSourceDefinition(
        in: session,
        definitionName: definitionName,
        bodyCount: 1
    )
    return try #require(featureIDs.first)
}

@MainActor
@discardableResult
private func createPatternSourceDefinition(
    in session: EditorSession,
    definitionName: String,
    bodyCount: Int
) throws -> [FeatureID] {
    var bodyFeatureIDs: [FeatureID] = []
    var bodySceneNodeIDs: [SceneNodeID] = []
    for _ in 0 ..< bodyCount {
        _ = try #require(session.createDefaultExtrudedRectangle())
        let bodyFeatureID = try #require(session.document.cadDocument.designGraph.order.last)
        bodyFeatureIDs.append(bodyFeatureID)
        bodySceneNodeIDs.append(try sceneNodeID(for: bodyFeatureID, in: session.document))
    }
    _ = try session.execute(
        .createComponentDefinition(
            name: definitionName,
            rootSceneNodeIDs: bodySceneNodeIDs
        )
    )
    return bodyFeatureIDs
}

private func outputSceneNodeID(
    for source: PatternArraySource,
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

private func renderableDescendantSceneNodeID(
    rootedAt rootSceneNodeID: SceneNodeID,
    scene: ViewportScene,
    document: DesignDocument
) throws -> SceneNodeID {
    let subtreeIDs = Set(sceneSubtreeIDs(rootedAt: rootSceneNodeID, document: document))
    return try #require(scene.items.compactMap(\.sceneNodeID).first { subtreeIDs.contains($0) })
}

private func bodyFeatureID(
    inSceneSubtreeRootedAt rootSceneNodeID: SceneNodeID,
    document: DesignDocument
) throws -> FeatureID {
    let subtreeIDs = Set(sceneSubtreeIDs(rootedAt: rootSceneNodeID, document: document))
    let bodySceneNode = try #require(document.productMetadata.sceneNodes.values.first { node in
        subtreeIDs.contains(node.id) && node.reference?.kind == .body
    })
    return try #require(bodySceneNode.reference?.featureID)
}

private func bodyItem(
    rootedAt rootSceneNodeID: SceneNodeID,
    source: PatternArraySource,
    scene: ViewportScene,
    document: DesignDocument
) throws -> ViewportSceneItem {
    let subtreeIDs = Set(sceneSubtreeIDs(rootedAt: rootSceneNodeID, document: document))
    return try #require(scene.items.first { item in
        guard let sceneNodeID = item.sceneNodeID else {
            return false
        }
        if case .body = item.kind {
            return subtreeIDs.contains(sceneNodeID) && source.outputFeatureIDs.contains(item.featureID)
        }
        return false
    })
}

private func bodyCenterY(for item: ViewportSceneItem) -> Double {
    guard case .body(let component) = item.kind,
          component.yMinMeters.isFinite,
          component.yMaxMeters.isFinite else {
        return 0.0
    }
    return (component.yMinMeters + component.yMaxMeters) * 0.5
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

private func sceneSubtreeIDs(
    rootedAt rootSceneNodeID: SceneNodeID,
    document: DesignDocument
) -> [SceneNodeID] {
    var result: [SceneNodeID] = []
    var visited: Set<SceneNodeID> = []
    appendSceneSubtreeIDs(
        rootSceneNodeID,
        document: document,
        visited: &visited,
        result: &result
    )
    return result
}

private func appendSceneSubtreeIDs(
    _ sceneNodeID: SceneNodeID,
    document: DesignDocument,
    visited: inout Set<SceneNodeID>,
    result: inout [SceneNodeID]
) {
    guard visited.insert(sceneNodeID).inserted else {
        return
    }
    result.append(sceneNodeID)
    guard let sceneNode = document.productMetadata.sceneNodes[sceneNodeID] else {
        return
    }
    for childID in sceneNode.childIDs {
        appendSceneSubtreeIDs(
            childID,
            document: document,
            visited: &visited,
            result: &result
        )
    }
}

private func projectedDirection(
    for axis: Vector3D,
    layout: ViewportLayout
) -> CGVector {
    let projected = CGVector(
        dx: (
            layout.basis.xDirection.dx * CGFloat(axis.x)
                + layout.basis.yDirection.dx * CGFloat(axis.y)
                + layout.basis.zDirection.dx * CGFloat(axis.z)
        ) * layout.scale,
        dy: (
            layout.basis.xDirection.dy * CGFloat(axis.x)
                + layout.basis.yDirection.dy * CGFloat(axis.y)
                + layout.basis.zDirection.dy * CGFloat(axis.z)
        ) * layout.scale
    )
    return projected.normalized
}
