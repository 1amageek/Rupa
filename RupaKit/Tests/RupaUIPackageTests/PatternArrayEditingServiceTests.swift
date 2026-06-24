import RupaCore
import Testing
@testable import RupaUI

@MainActor
@Test func patternArrayEditingServiceKeepsExpressionWhenChangingRectangularDistanceMode() async throws {
    let session = EditorSession()
    _ = try #require(session.createDefaultExtrudedRectangle())
    _ = try session.execute(
        .upsertParameter(
            name: "patternSpacing",
            expression: .constant(.length(10.0, unit: .millimeter)),
            kind: .length
        )
    )
    let spacing = try #require(
        session.document.cadDocument.parameters.parameters.values.first { $0.name == "patternSpacing" }
    )
    let sourceID = try createPatternArray(
        in: session,
        name: "Expression Array",
        distribution: .rectangular(RectangularPatternArray(
            firstAxis: PatternArrayLinearAxis(
                direction: .unitX,
                distance: .reference(spacing.id),
                copyCount: 3,
                distanceMode: .spacing
            )
        ))
    )
    let service = PatternArrayEditingService(session: session, sourceID: sourceID)

    let result = service.setRectangularAxisDistanceMode(slot: .first, distanceMode: .extent)

    let source = try #require(session.document.productMetadata.patternArrays[sourceID])
    guard case .rectangular(let rectangular) = source.distribution else {
        Issue.record("Expected a rectangular pattern array source.")
        return
    }
    #expect(result?.didMutate == true)
    #expect(rectangular.firstAxis.distanceMode == .extent)
    #expect(rectangular.firstAxis.distance == .reference(spacing.id))
}

@MainActor
@Test func patternArrayEditingServiceReplacesCurvePathWithSketchEntity() async throws {
    let session = EditorSession()
    _ = try #require(session.createDefaultExtrudedRectangle())
    let pathReference = try firstSketchCurveReference(in: session.document)
    let sourceID = try createPatternArray(
        in: session,
        name: "Sketch Path Array",
        distribution: .curve(CurvePatternArray(
            path: .polyline(
                points: [
                    .origin,
                    Point3D(x: 0.03, y: 0.0, z: 0.0),
                ],
                normal: .unitZ
            ),
            copyCount: 2
        ))
    )
    let service = PatternArrayEditingService(session: session, sourceID: sourceID)

    let result = service.setCurvePath(
        .sketchEntity(
            featureID: pathReference.featureID,
            entityID: pathReference.entityID
        )
    )

    let source = try #require(session.document.productMetadata.patternArrays[sourceID])
    guard case .curve(let curve) = source.distribution else {
        Issue.record("Expected a curve pattern array source.")
        return
    }
    #expect(result?.didMutate == true)
    #expect(curve.path == .sketchEntity(featureID: pathReference.featureID, entityID: pathReference.entityID))
    #expect(source.outputInstanceIDs.count == 2)
}

@MainActor
@Test func patternArrayCurvePathCandidateAcceptsOnlySketchCurves() throws {
    let target = SelectionTarget(
        sceneNodeID: SceneNodeID(),
        component: .sketchEntity(.sketchEntity(featureID: FeatureID(), entityID: SketchEntityID()))
    )
    let featureID = FeatureID()
    let entityID = SketchEntityID()

    let candidate = try #require(PatternArrayCurvePathCandidate(
        target: target,
        featureID: featureID,
        entityID: entityID,
        sourceFeatureName: "Sketch 1",
        entityKind: "line"
    ))

    #expect(candidate.title == "Sketch 1 Line")
    #expect(candidate.path == .sketchEntity(featureID: featureID, entityID: entityID))
    #expect(candidate.matches(.sketchEntity(featureID: featureID, entityID: entityID)))
    #expect(PatternArrayCurvePathCandidate(
        target: target,
        featureID: featureID,
        entityID: entityID,
        sourceFeatureName: "Sketch 1",
        entityKind: "point"
    ) == nil)
}

@MainActor
@Test func patternArrayCurvePathCandidateResolvesViewportSketchCurveTarget() async throws {
    let session = EditorSession()
    _ = try #require(session.createDefaultExtrudedRectangle())
    let pathReference = try firstSketchCurveReference(in: session.document)
    let target = SelectionTarget(
        sceneNodeID: pathReference.sceneNodeID,
        component: .sketchEntity(
            .sketchEntity(
                featureID: pathReference.featureID,
                entityID: pathReference.entityID
            )
        )
    )

    let candidate = try #require(PatternArrayCurvePathCandidate(
        target: target,
        document: session.document
    ))

    #expect(candidate.target == target)
    #expect(candidate.path == .sketchEntity(featureID: pathReference.featureID, entityID: pathReference.entityID))
}

@MainActor
@Test func patternArrayCurvePathPickServiceAppliesViewportCurveWithoutReplacingArraySelection() async throws {
    let session = EditorSession()
    _ = try #require(session.createDefaultExtrudedRectangle())
    let pathReference = try firstSketchCurveReference(in: session.document)
    let target = SelectionTarget(
        sceneNodeID: pathReference.sceneNodeID,
        component: .sketchEntity(
            .sketchEntity(
                featureID: pathReference.featureID,
                entityID: pathReference.entityID
            )
        )
    )
    let sourceID = try createPatternArray(
        in: session,
        name: "Viewport Pick Array",
        distribution: .curve(CurvePatternArray(
            path: .polyline(
                points: [
                    .origin,
                    Point3D(x: 0.03, y: 0.0, z: 0.0),
                ],
                normal: .unitZ
            ),
            copyCount: 2
        ))
    )
    let source = try #require(session.document.productMetadata.patternArrays[sourceID])
    let selectedSourceTarget = SelectionTarget(sceneNodeID: source.rootSceneNodeID)
    _ = session.selectTarget(selectedSourceTarget)
    let expectedCandidate = try #require(PatternArrayCurvePathCandidate(
        target: target,
        document: session.document
    ))

    let outcome = PatternArrayCurvePathPickService(
        session: session,
        sourceID: sourceID
    ).apply(targets: [target])

    let updatedSource = try #require(session.document.productMetadata.patternArrays[sourceID])
    guard case .curve(let curve) = updatedSource.distribution else {
        Issue.record("Expected a curve pattern array source.")
        return
    }
    #expect(outcome == .applied(expectedCandidate))
    #expect(curve.path == .sketchEntity(featureID: pathReference.featureID, entityID: pathReference.entityID))
    #expect(session.selection.selectedTargets == [selectedSourceTarget])
}

@MainActor
@Test func patternArrayEditingServiceClampsCurveExtentRatioToPlannerRange() async throws {
    let session = EditorSession()
    _ = try #require(session.createDefaultExtrudedRectangle())
    let sourceID = try createPatternArray(
        in: session,
        name: "Ratio Clamp Array",
        distribution: .curve(CurvePatternArray(
            path: .polyline(
                points: [
                    .origin,
                    Point3D(x: 0.03, y: 0.0, z: 0.0),
                ],
                normal: .unitZ
            ),
            copyCount: 2,
            extent: .scalar(0.5),
            extentMode: .ratio
        ))
    )
    let service = PatternArrayEditingService(session: session, sourceID: sourceID)

    let result = service.setCurveExtentRatio(2.0)

    let source = try #require(session.document.productMetadata.patternArrays[sourceID])
    guard case .curve(let curve) = source.distribution,
          case .constant(let quantity) = curve.extent else {
        Issue.record("Expected a constant ratio extent.")
        return
    }
    #expect(result?.didMutate == true)
    #expect(curve.extentMode == .ratio)
    #expect(quantity.kind == .scalar)
    #expect(quantity.value == 1.0)
}

@MainActor
private func createPatternArray(
    in session: EditorSession,
    name: String,
    distribution: PatternArrayDistribution
) throws -> PatternArraySourceID {
    let bodyFeatureID = try #require(session.document.cadDocument.designGraph.order.last)
    let bodySceneNodeID = try sceneNodeID(for: bodyFeatureID, in: session.document)
    _ = try session.execute(
        .createComponentDefinition(
            name: "\(name) Source",
            rootSceneNodeIDs: [bodySceneNodeID]
        )
    )
    let definition = try #require(session.document.productMetadata.componentDefinitions.values.first {
        $0.name == "\(name) Source"
    })
    _ = try session.execute(
        .createPatternArray(
            name: name,
            definitionID: definition.id,
            distribution: distribution,
            outputMode: .componentInstance
        )
    )
    return try #require(session.document.productMetadata.patternArrays.values.first { $0.name == name }?.id)
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

private func firstSketchCurveReference(
    in document: DesignDocument
) throws -> (featureID: FeatureID, entityID: SketchEntityID, sceneNodeID: SceneNodeID) {
    for featureID in document.cadDocument.designGraph.order {
        guard let node = document.cadDocument.designGraph.nodes[featureID],
              case .sketch(let sketch) = node.operation else {
            continue
        }
        for (entityID, entity) in sketch.entities {
            switch entity {
            case .line, .circle, .arc, .spline:
                return (
                    featureID,
                    entityID,
                    try sceneNodeID(for: featureID, in: document)
                )
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
