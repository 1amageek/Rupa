import CoreGraphics
import RupaCore
import SwiftCAD
import Testing
@testable import RupaRendering

@MainActor
@Test func patternArrayLinearAxisAffordanceServiceResolvesRectangularAxisHandles() async throws {
    let session = EditorSession()
    _ = try createDefaultPatternSourceDefinition(
        in: session,
        definitionName: "Axis Handle Source"
    )
    let definition = try #require(session.document.productMetadata.componentDefinitions.values.first {
        $0.name == "Axis Handle Source"
    })
    _ = try session.execute(
        .createPatternArray(
            name: "Axis Handle Pattern",
            definitionID: definition.id,
            distribution: .rectangular(RectangularPatternArray(
                firstAxis: PatternArrayLinearAxis(
                    direction: .unitX,
                    distance: .length(0.1, .meter),
                    copyCount: 2,
                    distanceMode: .spacing
                ),
                secondAxis: PatternArrayLinearAxis(
                    direction: .unitZ,
                    distance: .length(0.04, .meter),
                    copyCount: 1,
                    distanceMode: .extent
                )
            )),
            outputMode: .componentInstance
        )
    )
    let source = try #require(session.document.productMetadata.patternArrays.values.first {
        $0.name == "Axis Handle Pattern"
    })
    let scene = ViewportSceneBuilder().build(document: session.document)
    let layout = try #require(ViewportLayout(
        scene: scene,
        size: CGSize(width: 900.0, height: 700.0)
    ))

    let candidates = ViewportPatternArrayLinearAxisAffordanceService().candidates(
        document: session.document,
        scene: scene,
        selection: SelectionModel(selectedTargets: [
            SelectionTarget(sceneNodeID: source.rootSceneNodeID),
        ]),
        layout: layout
    )

    #expect(candidates.map(\.target.axisSlot) == [.first, .second])
    #expect(candidates.map(\.target.distanceMode) == [.spacing, .extent])
    #expect(candidates.map(\.geometry.baseDistanceMeters) == [0.1, 0.04])
}

@MainActor
@Test func patternArrayLinearAxisAffordanceServiceResolvesOutputSelectionAndDragDistance() async throws {
    let session = EditorSession()
    _ = try createDefaultPatternSourceDefinition(
        in: session,
        definitionName: "Output Axis Handle Source"
    )
    let definition = try #require(session.document.productMetadata.componentDefinitions.values.first {
        $0.name == "Output Axis Handle Source"
    })
    _ = try session.execute(
        .createPatternArray(
            name: "Output Axis Handle Pattern",
            definitionID: definition.id,
            distribution: .rectangular(RectangularPatternArray(
                firstAxis: PatternArrayLinearAxis(
                    direction: .unitX,
                    distance: .length(0.08, .meter),
                    copyCount: 2
                )
            )),
            outputMode: .componentInstance
        )
    )
    let source = try #require(session.document.productMetadata.patternArrays.values.first {
        $0.name == "Output Axis Handle Pattern"
    })
    let outputSceneNodeID = try firstOutputSceneNodeID(source: source, document: session.document)
    let scene = ViewportSceneBuilder().build(document: session.document)
    let layout = try #require(ViewportLayout(
        scene: scene,
        size: CGSize(width: 900.0, height: 700.0)
    ))

    let candidates = ViewportPatternArrayLinearAxisAffordanceService().candidates(
        document: session.document,
        scene: scene,
        selection: SelectionModel(selectedTargets: [
            SelectionTarget(sceneNodeID: outputSceneNodeID),
        ]),
        layout: layout
    )

    let candidate = try #require(candidates.first)
    let start = candidate.geometry.projectedTip()
    let current = CGPoint(
        x: start.x + candidate.geometry.projectedDirection.dx * candidate.geometry.pointsPerMeter * 0.03,
        y: start.y + candidate.geometry.projectedDirection.dy * candidate.geometry.pointsPerMeter * 0.03
    )
    let collapsed = CGPoint(
        x: start.x - candidate.geometry.projectedDirection.dx * candidate.geometry.pointsPerMeter * 1.0,
        y: start.y - candidate.geometry.projectedDirection.dy * candidate.geometry.pointsPerMeter * 1.0
    )
    let minimumDistance = PatternArrayDistancePolicy.standard.minimumLinearDistanceMeters
    #expect(candidates.count == 1)
    #expect(candidate.target.sourceID == source.id)
    #expect(candidate.target.axisSlot == .first)
    #expect(abs(candidate.geometry.axisDistance(start: start, current: current) - 0.11) < 1.0e-9)
    #expect(abs(candidate.geometry.axisDistance(start: start, current: collapsed) - minimumDistance) < 1.0e-12)
}

@MainActor
@Test func patternArrayLinearAxisAffordanceServiceResolvesRadialAxisHandle() async throws {
    let session = EditorSession()
    _ = try createDefaultPatternSourceDefinition(
        in: session,
        definitionName: "Radial Linear Axis Source"
    )
    let definition = try #require(session.document.productMetadata.componentDefinitions.values.first {
        $0.name == "Radial Linear Axis Source"
    })
    _ = try session.execute(
        .createPatternArray(
            name: "Radial Linear Axis Pattern",
            definitionID: definition.id,
            distribution: .radial(RadialPatternArray(
                angularAxis: PatternArrayAngularAxis(
                    center: .origin,
                    axis: .unitZ,
                    angle: .angle(90.0, .degree),
                    copyCount: 3
                ),
                radialAxis: PatternArrayLinearAxis(
                    direction: .unitX,
                    distance: .length(0.05, .meter),
                    copyCount: 2,
                    distanceMode: .spacing
                )
            )),
            outputMode: .componentInstance
        )
    )
    let source = try #require(session.document.productMetadata.patternArrays.values.first {
        $0.name == "Radial Linear Axis Pattern"
    })
    let scene = ViewportSceneBuilder().build(document: session.document)
    let layout = try #require(ViewportLayout(
        scene: scene,
        size: CGSize(width: 900.0, height: 700.0)
    ))

    let candidates = ViewportPatternArrayLinearAxisAffordanceService().candidates(
        document: session.document,
        scene: scene,
        selection: SelectionModel(selectedTargets: [
            SelectionTarget(sceneNodeID: source.rootSceneNodeID),
        ]),
        layout: layout
    )

    let candidate = try #require(candidates.first)
    #expect(candidates.map(\.target.axisSlot) == [.radial])
    #expect(candidate.target.sourceID == source.id)
    #expect(candidate.target.distanceMode == .spacing)
    #expect(candidate.geometry.baseDistanceMeters == 0.05)
}

@MainActor
@discardableResult
private func createDefaultPatternSourceDefinition(
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
