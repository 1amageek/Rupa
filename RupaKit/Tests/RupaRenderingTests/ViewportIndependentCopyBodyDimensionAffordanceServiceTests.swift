import CoreGraphics
import RupaCore
import SwiftCAD
import Testing
@testable import RupaRendering

@MainActor
@Test func independentCopyBodyDimensionAffordanceResolvesBoxProfileHandles() async throws {
    let session = EditorSession()
    let source = try createIndependentCopyBoxPatternArray(
        in: session,
        definitionName: "Body Dimension Box Source",
        arrayName: "Body Dimension Box Array"
    )
    let firstOutputSceneNodeID = try #require(source.outputSceneNodeIDs.first)
    let scene = ViewportSceneBuilder().build(document: session.document, ruler: session.workspaceState.ruler)
    let layout = try #require(ViewportLayout(
        scene: scene,
        size: CGSize(width: 900.0, height: 700.0)
    ))

    let candidates = ViewportIndependentCopyBodyDimensionAffordanceService().candidates(
        document: session.document,
        scene: scene,
        selection: SelectionModel(selectedTargets: [
            SelectionTarget(sceneNodeID: firstOutputSceneNodeID),
        ]),
        layout: layout
    )

    let candidateKinds = Set(candidates.map(\.target.kind))
    #expect(candidates.count == 2)
    #expect(candidateKinds == [.sizeX, .sizeZ])
    #expect(candidates.allSatisfy { $0.target.sourceID == source.id })
    #expect(candidates.allSatisfy { $0.target.outputIndex == 0 })
    #expect(candidates.allSatisfy { $0.target.outputSceneNodeID == firstOutputSceneNodeID })
    #expect(candidates.allSatisfy { source.outputFeatureIDs.contains($0.target.featureID) })
    #expect(candidates.allSatisfy { $0.geometry.baseDistanceMeters > 0.0 })
}

@MainActor
@Test func independentCopyBodyDimensionAffordanceUsesEditedBoxCloneDimensions() async throws {
    let session = EditorSession()
    let source = try createIndependentCopyBoxPatternArray(
        in: session,
        definitionName: "Body Dimension Edited Box Source",
        arrayName: "Body Dimension Edited Box Array"
    )
    let firstOutputSceneNodeID = try #require(source.outputSceneNodeIDs.first)
    let firstCloneBodyFeatureID = try bodyFeatureID(
        inSceneSubtreeRootedAt: firstOutputSceneNodeID,
        document: session.document
    )
    _ = try session.execute(
        .setCubeDimensions(
            featureID: firstCloneBodyFeatureID,
            sizeX: .length(16.0, .millimeter),
            sizeY: .length(9.0, .millimeter),
            sizeZ: .length(12.0, .millimeter)
        )
    )
    let scene = ViewportSceneBuilder().build(document: session.document, ruler: session.workspaceState.ruler)
    let layout = try #require(ViewportLayout(
        scene: scene,
        size: CGSize(width: 900.0, height: 700.0)
    ))

    let candidates = ViewportIndependentCopyBodyDimensionAffordanceService().candidates(
        document: session.document,
        scene: scene,
        selection: SelectionModel(selectedTargets: [
            SelectionTarget(sceneNodeID: firstOutputSceneNodeID),
        ]),
        layout: layout
    )

    let sizeX = try #require(candidates.first { $0.target.kind == .sizeX })
    let sizeZ = try #require(candidates.first { $0.target.kind == .sizeZ })
    #expect(sizeX.target.featureID == firstCloneBodyFeatureID)
    #expect(sizeZ.target.featureID == firstCloneBodyFeatureID)
    #expect(abs(sizeX.geometry.baseDistanceMeters - 0.016) < 1.0e-12)
    #expect(abs(sizeZ.geometry.baseDistanceMeters - 0.012) < 1.0e-12)
}

@MainActor
@Test func independentCopyBodyDimensionAffordanceAppliesOutputScaleToDisplayedDimensions() async throws {
    let session = EditorSession()
    let source = try createIndependentCopyBoxPatternArray(
        in: session,
        definitionName: "Body Dimension Scaled Box Source",
        arrayName: "Body Dimension Scaled Box Array",
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

    let candidates = ViewportIndependentCopyBodyDimensionAffordanceService().candidates(
        document: session.document,
        scene: scene,
        selection: SelectionModel(selectedTargets: [
            SelectionTarget(sceneNodeID: firstOutputSceneNodeID),
        ]),
        layout: layout
    )

    let sizeX = try #require(candidates.first { $0.target.kind == .sizeX })
    #expect(abs(sizeX.target.valueScale - 2.0) < 1.0e-12)
    #expect(abs(sizeX.geometry.baseDistanceMeters - 0.080) < 1.0e-12)
}

@MainActor
@Test func independentCopyBodyDimensionAffordanceUsesSceneTransformedBodyEdgeAsBasePoint() async throws {
    let session = EditorSession()
    let source = try createIndependentCopyBoxPatternArray(
        in: session,
        definitionName: "Body Dimension Base Point Box Source",
        arrayName: "Body Dimension Base Point Box Array",
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

    let candidates = ViewportIndependentCopyBodyDimensionAffordanceService().candidates(
        document: session.document,
        scene: scene,
        selection: SelectionModel(selectedTargets: [
            SelectionTarget(sceneNodeID: firstOutputSceneNodeID),
        ]),
        layout: layout
    )

    let sizeX = try #require(candidates.first { $0.target.kind == .sizeX })
    let expectedBasePoint = layout.project(Point3D(
        x: Double(outputBodyItem.modelBounds.minX),
        y: bodyCenterY(for: outputBodyItem),
        z: Double(outputBodyItem.modelBounds.midY)
    ))
    #expect(abs(sizeX.geometry.baseProjectedPoint.x - expectedBasePoint.x) < 1.0e-9)
    #expect(abs(sizeX.geometry.baseProjectedPoint.y - expectedBasePoint.y) < 1.0e-9)
}

@MainActor
@Test func independentCopyBodyDimensionAffordanceAppliesOutputRotationToHandleAxis() async throws {
    let session = EditorSession()
    let source = try createIndependentCopyBoxPatternArray(
        in: session,
        definitionName: "Body Dimension Rotated Box Source",
        arrayName: "Body Dimension Rotated Box Array",
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

    let candidates = ViewportIndependentCopyBodyDimensionAffordanceService().candidates(
        document: session.document,
        scene: scene,
        selection: SelectionModel(selectedTargets: [
            SelectionTarget(sceneNodeID: firstOutputSceneNodeID),
        ]),
        layout: layout
    )

    let sizeX = try #require(candidates.first { $0.target.kind == .sizeX })
    let expectedDirection = projectedDirection(
        for: outputTransform.viewportTransformedVector(.unitX),
        layout: layout
    )
    #expect(abs(sizeX.geometry.projectedDirection.dx - expectedDirection.dx) < 1.0e-12)
    #expect(abs(sizeX.geometry.projectedDirection.dy - expectedDirection.dy) < 1.0e-12)
}

@MainActor
@Test func independentCopyBodyDimensionAffordanceResolvesCylinderRadiusHandle() async throws {
    let session = EditorSession()
    let source = try createIndependentCopyCylinderPatternArray(
        in: session,
        definitionName: "Body Dimension Cylinder Source",
        arrayName: "Body Dimension Cylinder Array"
    )
    let firstOutputSceneNodeID = try #require(source.outputSceneNodeIDs.first)
    let firstCloneBodyFeatureID = try bodyFeatureID(
        inSceneSubtreeRootedAt: firstOutputSceneNodeID,
        document: session.document
    )
    _ = try session.execute(
        .setCylinderDimensions(
            featureID: firstCloneBodyFeatureID,
            radius: .length(7.0, .millimeter),
            sizeY: .length(13.0, .millimeter)
        )
    )
    let scene = ViewportSceneBuilder().build(document: session.document, ruler: session.workspaceState.ruler)
    let layout = try #require(ViewportLayout(
        scene: scene,
        size: CGSize(width: 900.0, height: 700.0)
    ))

    let candidates = ViewportIndependentCopyBodyDimensionAffordanceService().candidates(
        document: session.document,
        scene: scene,
        selection: SelectionModel(selectedTargets: [
            SelectionTarget(sceneNodeID: firstOutputSceneNodeID),
        ]),
        layout: layout
    )

    let radius = try #require(candidates.first)
    #expect(candidates.count == 1)
    #expect(radius.target.kind == .radius)
    #expect(radius.target.featureID == firstCloneBodyFeatureID)
    #expect(abs(radius.geometry.baseDistanceMeters - 0.007) < 1.0e-12)
}

@MainActor
@Test func independentCopyBodyDimensionAffordanceIgnoresComponentInstanceOutputs() async throws {
    let session = EditorSession()
    _ = try createBoxPatternSourceDefinition(
        in: session,
        definitionName: "Body Dimension Component Source"
    )
    let definition = try #require(session.document.productMetadata.componentDefinitions.values.first {
        $0.name == "Body Dimension Component Source"
    })
    _ = try session.execute(
        .createPatternArray(
            name: "Body Dimension Component Array",
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
        $0.name == "Body Dimension Component Array"
    })
    let outputSceneNodeID = try componentOutputSceneNodeID(for: source, document: session.document)
    let scene = ViewportSceneBuilder().build(document: session.document, ruler: session.workspaceState.ruler)
    let layout = try #require(ViewportLayout(
        scene: scene,
        size: CGSize(width: 900.0, height: 700.0)
    ))

    let candidates = ViewportIndependentCopyBodyDimensionAffordanceService().candidates(
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
private func createIndependentCopyBoxPatternArray(
    in session: EditorSession,
    definitionName: String,
    arrayName: String,
    distribution: PatternArrayDistribution? = nil
) throws -> PatternArraySource {
    _ = try createBoxPatternSourceDefinition(
        in: session,
        definitionName: definitionName
    )
    return try createIndependentCopyPatternArray(
        in: session,
        definitionName: definitionName,
        arrayName: arrayName,
        distribution: distribution
    )
}

@MainActor
private func createIndependentCopyCylinderPatternArray(
    in session: EditorSession,
    definitionName: String,
    arrayName: String
) throws -> PatternArraySource {
    _ = try createCylinderPatternSourceDefinition(
        in: session,
        definitionName: definitionName
    )
    return try createIndependentCopyPatternArray(
        in: session,
        definitionName: definitionName,
        arrayName: arrayName
    )
}

@MainActor
@discardableResult
private func createBoxPatternSourceDefinition(
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

@MainActor
@discardableResult
private func createCylinderPatternSourceDefinition(
    in session: EditorSession,
    definitionName: String
) throws -> FeatureID {
    _ = try session.execute(
        .createExtrudedCircle(
            name: "\(definitionName) Body",
            plane: .xy,
            center: SketchPoint(
                x: .length(0.0, .millimeter),
                y: .length(0.0, .millimeter)
            ),
            radius: .length(5.0, .millimeter),
            depth: .length(8.0, .millimeter),
            direction: .normal
        )
    )
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

@MainActor
private func createIndependentCopyPatternArray(
    in session: EditorSession,
    definitionName: String,
    arrayName: String,
    distribution: PatternArrayDistribution? = nil
) throws -> PatternArraySource {
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

private func componentOutputSceneNodeID(
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
