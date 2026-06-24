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
@Test func patternArrayCopyCountAffordanceServiceResolvesRectangularExtentDensityCounts() async throws {
    let session = EditorSession()
    _ = try createDefaultCopyCountPatternSourceDefinition(
        in: session,
        definitionName: "Rectangular Extent Density Source"
    )
    let definition = try #require(session.document.productMetadata.componentDefinitions.values.first {
        $0.name == "Rectangular Extent Density Source"
    })
    _ = try session.execute(
        .createPatternArray(
            name: "Rectangular Extent Density Pattern",
            definitionID: definition.id,
            distribution: .rectangular(RectangularPatternArray(
                firstAxis: PatternArrayLinearAxis(
                    direction: .unitX,
                    distance: .length(0.08, .meter),
                    copyCount: 4,
                    distanceMode: .extent
                ),
                secondAxis: PatternArrayLinearAxis(
                    direction: .unitZ,
                    distance: .length(0.05, .meter),
                    copyCount: 2,
                    distanceMode: .extent
                )
            )),
            outputMode: .componentInstance
        )
    )
    let source = try #require(session.document.productMetadata.patternArrays.values.first {
        $0.name == "Rectangular Extent Density Pattern"
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
    #expect(candidates.map(\.geometry.baseCopyCount) == [4, 2])
    let firstCandidate = try #require(candidates.first { $0.target.slot == .rectangularFirst })
    let secondCandidate = try #require(candidates.first { $0.target.slot == .rectangularSecond })
    #expect(firstCandidate.geometry.copyCount(
        start: firstCandidate.geometry.handlePoint,
        current: firstCandidate.geometry.handlePoint(copyCount: 6)
    ) == 6)
    #expect(secondCandidate.geometry.copyCount(
        start: secondCandidate.geometry.handlePoint,
        current: secondCandidate.geometry.handlePoint(copyCount: 1)
    ) == 1)
    #expect(firstCandidate.geometry.guidePoints().count == 4)
    #expect(secondCandidate.geometry.guidePoints().count == 4)
}

@MainActor
@Test func patternArrayCopyCountAffordanceServiceResolvesReferencedLinearDistance() async throws {
    let session = EditorSession()
    _ = try createDefaultCopyCountPatternSourceDefinition(
        in: session,
        definitionName: "Referenced Count Source"
    )
    _ = try session.execute(
        .upsertParameter(
            name: "countSpacing",
            expression: .constant(.length(45.0, unit: .millimeter)),
            kind: .length
        )
    )
    let spacing = try #require(session.document.cadDocument.parameters.parameters.values.first {
        $0.name == "countSpacing"
    })
    let definition = try #require(session.document.productMetadata.componentDefinitions.values.first {
        $0.name == "Referenced Count Source"
    })
    _ = try session.execute(
        .createPatternArray(
            name: "Referenced Count Pattern",
            definitionID: definition.id,
            distribution: .rectangular(RectangularPatternArray(
                firstAxis: PatternArrayLinearAxis(
                    direction: .unitX,
                    distance: .reference(spacing.id),
                    copyCount: 3,
                    distanceMode: .spacing
                )
            )),
            outputMode: .componentInstance
        )
    )
    let source = try #require(session.document.productMetadata.patternArrays.values.first {
        $0.name == "Referenced Count Pattern"
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

    let candidate = try #require(candidates.first)
    #expect(candidates.map(\.target.slot) == [.rectangularFirst])
    #expect(candidate.geometry.baseCopyCount == 3)
    #expect(candidate.geometry.copyCount(
        start: candidate.geometry.handlePoint,
        current: candidate.geometry.handlePoint(copyCount: 5)
    ) == 5)
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
@Test func patternArrayCopyCountAffordanceServiceResolvesReferencedAngularDistance() async throws {
    let session = EditorSession()
    _ = try createDefaultCopyCountPatternSourceDefinition(
        in: session,
        definitionName: "Referenced Angular Count Source"
    )
    _ = try session.execute(
        .upsertParameter(
            name: "countAngle",
            expression: .constant(.angle(45.0, unit: .degree)),
            kind: .angle
        )
    )
    let angle = try #require(session.document.cadDocument.parameters.parameters.values.first {
        $0.name == "countAngle"
    })
    let definition = try #require(session.document.productMetadata.componentDefinitions.values.first {
        $0.name == "Referenced Angular Count Source"
    })
    _ = try session.execute(
        .createPatternArray(
            name: "Referenced Angular Count Pattern",
            definitionID: definition.id,
            distribution: .radial(RadialPatternArray(
                angularAxis: PatternArrayAngularAxis(
                    center: .origin,
                    axis: .unitZ,
                    angle: .reference(angle.id),
                    copyCount: 4,
                    angleMode: .spacing
                )
            )),
            outputMode: .componentInstance
        )
    )
    let source = try #require(session.document.productMetadata.patternArrays.values.first {
        $0.name == "Referenced Angular Count Pattern"
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

    let candidate = try #require(candidates.first)
    #expect(candidates.map(\.target.slot) == [.radialAngular])
    #expect(candidate.geometry.baseCopyCount == 4)
    #expect(candidate.geometry.copyCount(
        start: candidate.geometry.handlePoint,
        current: candidate.geometry.handlePoint(copyCount: 6)
    ) == 6)
}

@MainActor
@Test func patternArrayCopyCountAffordanceServiceResolvesCurveCountsFromOutputSelection() async throws {
    let session = EditorSession()
    _ = try createDefaultCopyCountPatternSourceDefinition(
        in: session,
        definitionName: "Curve Count Source"
    )
    let definition = try #require(session.document.productMetadata.componentDefinitions.values.first {
        $0.name == "Curve Count Source"
    })
    _ = try session.execute(
        .createPatternArray(
            name: "Curve Count Pattern",
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
                extent: .scalar(0.75),
                extentMode: .ratio
            )),
            outputMode: .componentInstance
        )
    )
    let source = try #require(session.document.productMetadata.patternArrays.values.first {
        $0.name == "Curve Count Pattern"
    })
    let outputSceneNodeID = try firstCopyCountOutputSceneNodeID(source: source, document: session.document)
    let scene = ViewportSceneBuilder().build(document: session.document)
    let layout = try #require(ViewportLayout(scene: scene, size: CGSize(width: 900.0, height: 700.0)))

    let candidates = ViewportPatternArrayCopyCountAffordanceService().candidates(
        document: session.document,
        scene: scene,
        selection: SelectionModel(selectedTargets: [
            SelectionTarget(sceneNodeID: outputSceneNodeID),
        ]),
        layout: layout
    )

    let candidate = try #require(candidates.first)
    #expect(candidates.map(\.target.slot) == [.curve])
    #expect(candidate.target.sourceID == source.id)
    #expect(candidate.geometry.baseCopyCount == 3)
    #expect(candidate.geometry.copyCount(
        start: candidate.geometry.handlePoint,
        current: candidate.geometry.handlePoint(copyCount: 5)
    ) == 5)
    #expect(candidate.geometry.copyCount(
        start: candidate.geometry.handlePoint,
        current: candidate.geometry.handlePoint(copyCount: 1)
    ) == 1)
    #expect(candidate.geometry.guidePoints().count > 3)
}

@MainActor
@Test func patternArrayCopyCountAffordanceServiceResolvesRadialExtentDensityCounts() async throws {
    let session = EditorSession()
    _ = try createDefaultCopyCountPatternSourceDefinition(
        in: session,
        definitionName: "Radial Extent Density Source"
    )
    let definition = try #require(session.document.productMetadata.componentDefinitions.values.first {
        $0.name == "Radial Extent Density Source"
    })
    _ = try session.execute(
        .createPatternArray(
            name: "Radial Extent Density Pattern",
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
        $0.name == "Radial Extent Density Pattern"
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
    #expect(candidates.map(\.geometry.baseCopyCount) == [3, 2])
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
    #expect(angularCandidate.geometry.guidePoints().count > 3)
    #expect(radialAxisCandidate.geometry.guidePoints().count == 4)
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

private func firstCopyCountOutputSceneNodeID(
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
