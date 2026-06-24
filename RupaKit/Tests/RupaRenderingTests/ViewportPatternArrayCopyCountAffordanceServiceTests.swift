import CoreGraphics
import RupaCore
import SwiftCAD
import Testing
@testable import RupaRendering

@MainActor
@Test func patternArrayCopyCountAffordanceServiceResolvesRectangularSpacingCounts() async throws {
    let session = EditorSession()
    _ = try createDefaultCopyCountPatternSourceDefinition(
        in: session,
        definitionName: "Rectangular Count Source"
    )
    let definition = try #require(session.document.productMetadata.componentDefinitions.values.first {
        $0.name == "Rectangular Count Source"
    })
    _ = try session.execute(
        .createPatternArray(
            name: "Rectangular Count Pattern",
            definitionID: definition.id,
            distribution: .rectangular(RectangularPatternArray(
                firstAxis: PatternArrayLinearAxis(
                    direction: .unitX,
                    distance: .length(0.04, .meter),
                    copyCount: 3,
                    distanceMode: .spacing
                ),
                secondAxis: PatternArrayLinearAxis(
                    direction: .unitZ,
                    distance: .length(0.03, .meter),
                    copyCount: 2,
                    distanceMode: .spacing
                )
            )),
            outputMode: .componentInstance
        )
    )
    let source = try #require(session.document.productMetadata.patternArrays.values.first {
        $0.name == "Rectangular Count Pattern"
    })
    let scene = ViewportSceneBuilder().build(document: session.document)
    let layout = try #require(ViewportLayout(scene: scene, size: CGSize(width: 900.0, height: 700.0)))

    let candidates = ViewportPatternArrayCopyCountAffordanceService().candidates(
        document: session.document,
        scene: scene,
        selection: SelectionModel(selectedTargets: [
            SelectionTarget(sceneNodeID: source.rootSceneNodeID),
        ]),
        layout: layout
    )

    #expect(candidates.map(\.target.slot) == [.rectangularFirst, .rectangularSecond])
    #expect(candidates.map(\.geometry.baseCopyCount) == [3, 2])
    let firstCandidate = try #require(candidates.first)
    #expect(firstCandidate.geometry.copyCount(
        start: firstCandidate.geometry.handlePoint,
        current: firstCandidate.geometry.handlePoint(copyCount: 4)
    ) == 4)
}

@MainActor
@Test func patternArrayCopyCountAffordanceServiceResolvesRadialSpacingCounts() async throws {
    let session = EditorSession()
    _ = try createDefaultCopyCountPatternSourceDefinition(
        in: session,
        definitionName: "Radial Count Source"
    )
    let definition = try #require(session.document.productMetadata.componentDefinitions.values.first {
        $0.name == "Radial Count Source"
    })
    _ = try session.execute(
        .createPatternArray(
            name: "Radial Count Pattern",
            definitionID: definition.id,
            distribution: .radial(RadialPatternArray(
                angularAxis: PatternArrayAngularAxis(
                    center: .origin,
                    axis: .unitZ,
                    angle: .angle(45.0, .degree),
                    copyCount: 4,
                    angleMode: .spacing
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
        $0.name == "Radial Count Pattern"
    })
    let scene = ViewportSceneBuilder().build(document: session.document)
    let layout = try #require(ViewportLayout(scene: scene, size: CGSize(width: 900.0, height: 700.0)))

    let candidates = ViewportPatternArrayCopyCountAffordanceService().candidates(
        document: session.document,
        scene: scene,
        selection: SelectionModel(selectedTargets: [
            SelectionTarget(sceneNodeID: source.rootSceneNodeID),
        ]),
        layout: layout
    )

    #expect(candidates.map(\.target.slot) == [.radialAngular, .radialAxis])
    #expect(candidates.map(\.geometry.baseCopyCount) == [4, 2])
    let angularCandidate = try #require(candidates.first { $0.target.slot == .radialAngular })
    let radialAxisCandidate = try #require(candidates.first { $0.target.slot == .radialAxis })
    #expect(angularCandidate.geometry.copyCount(
        start: angularCandidate.geometry.handlePoint,
        current: angularCandidate.geometry.handlePoint(copyCount: 5)
    ) == 5)
    #expect(radialAxisCandidate.geometry.copyCount(
        start: radialAxisCandidate.geometry.handlePoint,
        current: radialAxisCandidate.geometry.handlePoint(copyCount: 3)
    ) == 3)
}

@MainActor
@Test func patternArrayCopyCountAffordanceServiceSkipsExtentModeCounts() async throws {
    let session = EditorSession()
    _ = try createDefaultCopyCountPatternSourceDefinition(
        in: session,
        definitionName: "Extent Count Source"
    )
    let definition = try #require(session.document.productMetadata.componentDefinitions.values.first {
        $0.name == "Extent Count Source"
    })
    _ = try session.execute(
        .createPatternArray(
            name: "Extent Count Pattern",
            definitionID: definition.id,
            distribution: .radial(RadialPatternArray(
                angularAxis: PatternArrayAngularAxis(
                    center: .origin,
                    axis: .unitZ,
                    angle: .angle(90.0, .degree),
                    copyCount: 3,
                    angleMode: .extent
                ),
                radialAxis: PatternArrayLinearAxis(
                    direction: .unitX,
                    distance: .length(0.05, .meter),
                    copyCount: 2,
                    distanceMode: .extent
                )
            )),
            outputMode: .componentInstance
        )
    )
    let source = try #require(session.document.productMetadata.patternArrays.values.first {
        $0.name == "Extent Count Pattern"
    })
    let scene = ViewportSceneBuilder().build(document: session.document)
    let layout = try #require(ViewportLayout(scene: scene, size: CGSize(width: 900.0, height: 700.0)))

    let candidates = ViewportPatternArrayCopyCountAffordanceService().candidates(
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
private func createDefaultCopyCountPatternSourceDefinition(
    in session: EditorSession,
    definitionName: String
) throws -> FeatureID {
    _ = try #require(session.createDefaultExtrudedRectangle())
    let bodyFeatureID = try #require(session.document.cadDocument.designGraph.order.last)
    let bodySceneNodeID = try copyCountSceneNodeID(for: bodyFeatureID, in: session.document)
    _ = try session.execute(
        .createComponentDefinition(
            name: definitionName,
            rootSceneNodeIDs: [bodySceneNodeID]
        )
    )
    return bodyFeatureID
}

private func copyCountSceneNodeID(
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
