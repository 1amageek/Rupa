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
@Test func patternArrayEditingServiceSetsRectangularAxisDistanceFromViewportDrag() async throws {
    let session = EditorSession()
    _ = try #require(session.createDefaultExtrudedRectangle())
    let sourceID = try createPatternArray(
        in: session,
        name: "Viewport Distance Array",
        distribution: .rectangular(RectangularPatternArray(
            firstAxis: PatternArrayLinearAxis(
                direction: .unitX,
                distance: .length(10.0, .millimeter),
                copyCount: 3,
                distanceMode: .spacing
            )
        ))
    )
    let service = PatternArrayEditingService(session: session, sourceID: sourceID)

    let result = service.setRectangularAxisDistance(slot: .first, meters: 0.024)

    let source = try #require(session.document.productMetadata.patternArrays[sourceID])
    guard case .rectangular(let rectangular) = source.distribution,
          case .constant(let distance) = rectangular.firstAxis.distance else {
        Issue.record("Expected a rectangular pattern array source with constant first-axis distance.")
        return
    }
    #expect(result?.didMutate == true)
    #expect(rectangular.firstAxis.distanceMode == .spacing)
    #expect(distance.kind == .length)
    #expect(distance.value == 0.024)
}

@MainActor
@Test func patternArrayEditingServiceUpdatesReferencedRectangularDistanceParameter() async throws {
    let session = EditorSession()
    _ = try #require(session.createDefaultExtrudedRectangle())
    _ = try session.execute(
        .upsertParameter(
            name: "editablePatternSpacing",
            expression: .constant(.length(10.0, unit: .millimeter)),
            kind: .length
        )
    )
    let spacing = try #require(session.document.cadDocument.parameters.parameters.values.first {
        $0.name == "editablePatternSpacing"
    })
    let sourceID = try createPatternArray(
        in: session,
        name: "Referenced Viewport Distance Array",
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

    let result = service.setRectangularAxisDistance(slot: .first, meters: 0.024)

    let source = try #require(session.document.productMetadata.patternArrays[sourceID])
    guard case .rectangular(let rectangular) = source.distribution,
          case .reference(let parameterID) = rectangular.firstAxis.distance else {
        Issue.record("Expected the rectangular axis to keep the parameter reference.")
        return
    }
    let quantity = try parameterQuantity(named: "editablePatternSpacing", in: session.document)
    #expect(result?.didMutate == true)
    #expect(parameterID == spacing.id)
    #expect(quantity.kind == .length)
    #expect(quantity.value == 0.024)
}

@MainActor
@Test func patternArrayExpressionWritebackBlocksKindMismatchWithoutDroppingReference() async throws {
    let session = EditorSession()
    _ = try session.execute(
        .upsertParameter(
            name: "editablePatternAngleOnly",
            expression: .constant(.angle(45.0, unit: .degree)),
            kind: .angle
        )
    )
    let angle = try #require(session.document.cadDocument.parameters.parameters.values.first {
        $0.name == "editablePatternAngleOnly"
    })

    let result = PatternArrayExpressionWritebackService(session: session).updateReferencedExpression(
        .reference(angle.id),
        quantity: .length(0.024, unit: .meter)
    )

    guard case .blocked = try #require(result) else {
        Issue.record("Expected kind-mismatched parameter writeback to block.")
        return
    }
    let parameter = try #require(session.document.cadDocument.parameters.parameters[angle.id])
    guard case .constant(let quantity) = parameter.expression else {
        Issue.record("Expected the parameter expression to remain unchanged.")
        return
    }
    #expect(quantity.kind == .angle)
    #expect(abs(quantity.value - Double.pi / 4.0) < 1.0e-12)
    #expect(session.diagnostics.contains {
        $0.severity == .warning && $0.message == "Pattern Array parameter reference could not be updated."
    })
}

@MainActor
@Test func patternArrayEditingServiceUpdatesReferencedRadialAndCurveParameters() async throws {
    let session = EditorSession()
    _ = try #require(session.createDefaultExtrudedRectangle())
    _ = try session.execute(
        .upsertParameter(
            name: "editablePatternAngle",
            expression: .constant(.angle(45.0, unit: .degree)),
            kind: .angle
        )
    )
    _ = try session.execute(
        .upsertParameter(
            name: "editablePatternTwist",
            expression: .constant(.angle(15.0, unit: .degree)),
            kind: .angle
        )
    )
    _ = try session.execute(
        .upsertParameter(
            name: "editablePatternScale",
            expression: .constant(.scalar(1.5)),
            kind: .scalar
        )
    )
    _ = try session.execute(
        .upsertParameter(
            name: "editablePatternRatio",
            expression: .constant(.scalar(0.5)),
            kind: .scalar
        )
    )
    let angle = try #require(session.document.cadDocument.parameters.parameters.values.first {
        $0.name == "editablePatternAngle"
    })
    let twist = try #require(session.document.cadDocument.parameters.parameters.values.first {
        $0.name == "editablePatternTwist"
    })
    let scale = try #require(session.document.cadDocument.parameters.parameters.values.first {
        $0.name == "editablePatternScale"
    })
    let ratio = try #require(session.document.cadDocument.parameters.parameters.values.first {
        $0.name == "editablePatternRatio"
    })
    let radialSourceID = try createPatternArray(
        in: session,
        name: "Referenced Radial Parameter Array",
        distribution: .radial(RadialPatternArray(
            angularAxis: PatternArrayAngularAxis(
                center: .origin,
                axis: .unitZ,
                angle: .reference(angle.id),
                copyCount: 3
            )
        ))
    )
    let curveSourceID = try createPatternArray(
        in: session,
        name: "Referenced Curve Parameter Array",
        distribution: .curve(CurvePatternArray(
            path: .polyline(
                points: [
                    .origin,
                    Point3D(x: 0.03, y: 0.0, z: 0.0),
                ],
                normal: .unitZ
            ),
            copyCount: 2,
            twist: .reference(twist.id),
            endScale: .reference(scale.id),
            extent: .reference(ratio.id),
            extentMode: .ratio
        ))
    )

    let radialResult = PatternArrayEditingService(
        session: session,
        sourceID: radialSourceID
    ).setRadialAngle(degrees: 90.0)
    let curveService = PatternArrayEditingService(session: session, sourceID: curveSourceID)
    let twistResult = curveService.setCurveTwist(degrees: 30.0)
    let scaleResult = curveService.setCurveEndScale(2.0)
    let ratioResult = curveService.setCurveExtentRatio(0.75)

    let radialSource = try #require(session.document.productMetadata.patternArrays[radialSourceID])
    let curveSource = try #require(session.document.productMetadata.patternArrays[curveSourceID])
    guard case .radial(let radial) = radialSource.distribution,
          case .reference(let radialAngleID) = radial.angularAxis.angle,
          case .curve(let curve) = curveSource.distribution,
          case .reference(let twistID) = curve.twist,
          case .reference(let scaleID) = curve.endScale,
          case .reference(let ratioID) = curve.extent else {
        Issue.record("Expected radial and curve controls to keep parameter references.")
        return
    }
    #expect(radialResult?.didMutate == true)
    #expect(twistResult?.didMutate == true)
    #expect(scaleResult?.didMutate == true)
    #expect(ratioResult?.didMutate == true)
    #expect(radialAngleID == angle.id)
    #expect(twistID == twist.id)
    #expect(scaleID == scale.id)
    #expect(ratioID == ratio.id)
    #expect(abs(try parameterQuantity(named: "editablePatternAngle", in: session.document).value - Double.pi / 2.0) < 1.0e-12)
    #expect(abs(try parameterQuantity(named: "editablePatternTwist", in: session.document).value - Double.pi / 6.0) < 1.0e-12)
    #expect(try parameterQuantity(named: "editablePatternScale", in: session.document).value == 2.0)
    #expect(try parameterQuantity(named: "editablePatternRatio", in: session.document).value == 0.75)
}

@MainActor
@Test func patternArrayEditingServiceSetsCopyCountsFromViewportDrag() async throws {
    let session = EditorSession()
    _ = try #require(session.createDefaultExtrudedRectangle())
    let rectangularSourceID = try createPatternArray(
        in: session,
        name: "Viewport Rectangular Count Array",
        distribution: .rectangular(RectangularPatternArray(
            firstAxis: PatternArrayLinearAxis(
                direction: .unitX,
                distance: .length(10.0, .millimeter),
                copyCount: 3
            ),
            secondAxis: PatternArrayLinearAxis(
                direction: .unitZ,
                distance: .length(12.0, .millimeter),
                copyCount: 2
            )
        ))
    )
    let radialSourceID = try createPatternArray(
        in: session,
        name: "Viewport Radial Count Array",
        distribution: .radial(RadialPatternArray(
            angularAxis: PatternArrayAngularAxis(
                center: .origin,
                axis: .unitZ,
                angle: .angle(45.0, .degree),
                copyCount: 4
            ),
            radialAxis: PatternArrayLinearAxis(
                direction: .unitX,
                distance: .length(10.0, .millimeter),
                copyCount: 2
            )
        ))
    )

    let rectangularService = PatternArrayEditingService(session: session, sourceID: rectangularSourceID)
    let radialService = PatternArrayEditingService(session: session, sourceID: radialSourceID)
    _ = rectangularService.setRectangularAxisCopyCount(slot: .first, copyCount: 5)
    _ = rectangularService.setRectangularAxisCopyCount(slot: .second, copyCount: 1)
    _ = radialService.setRadialAngularCopyCount(6)
    _ = radialService.setRadialAxisCopyCount(3)

    let rectangularSource = try #require(session.document.productMetadata.patternArrays[rectangularSourceID])
    let radialSource = try #require(session.document.productMetadata.patternArrays[radialSourceID])
    guard case .rectangular(let rectangular) = rectangularSource.distribution,
          case .radial(let radial) = radialSource.distribution else {
        Issue.record("Expected rectangular and radial pattern array sources.")
        return
    }
    #expect(rectangular.firstAxis.copyCount == 5)
    #expect(rectangular.secondAxis?.copyCount == 1)
    #expect(radial.angularAxis.copyCount == 6)
    #expect(radial.radialAxis?.copyCount == 3)
}

@MainActor
@Test func patternArrayEditingServiceNormalizesLinearDistancesToPlannerTolerance() async throws {
    let session = EditorSession()
    _ = try #require(session.createDefaultExtrudedRectangle())
    let minimumDistance = PatternArrayDistancePolicy.standard.minimumLinearDistanceMeters
    let rectangularSourceID = try createPatternArray(
        in: session,
        name: "Minimum Rectangular Distance Array",
        distribution: .rectangular(RectangularPatternArray(
            firstAxis: PatternArrayLinearAxis(
                direction: .unitX,
                distance: .length(10.0, .millimeter),
                copyCount: 3
            )
        ))
    )
    let radialSourceID = try createPatternArray(
        in: session,
        name: "Minimum Radial Distance Array",
        distribution: .radial(RadialPatternArray(
            angularAxis: PatternArrayAngularAxis(
                center: .origin,
                axis: .unitZ,
                angle: .angle(90.0, .degree),
                copyCount: 3
            ),
            radialAxis: PatternArrayLinearAxis(
                direction: .unitX,
                distance: .length(10.0, .millimeter),
                copyCount: 2
            )
        ))
    )
    let curveSourceID = try createPatternArray(
        in: session,
        name: "Minimum Curve Extent Array",
        distribution: .curve(CurvePatternArray(
            path: .polyline(
                points: [
                    .origin,
                    Point3D(x: 0.03, y: 0.0, z: 0.0),
                ],
                normal: .unitZ
            ),
            copyCount: 2,
            extent: .length(10.0, .millimeter),
            extentMode: .distance
        ))
    )

    let rectangularResult = PatternArrayEditingService(
        session: session,
        sourceID: rectangularSourceID
    ).setRectangularAxisDistance(slot: .first, meters: 1.0e-9)
    let radialResult = PatternArrayEditingService(
        session: session,
        sourceID: radialSourceID
    ).setRadialAxisDistance(1.0e-9)
    let curveResult = PatternArrayEditingService(
        session: session,
        sourceID: curveSourceID
    ).setCurveExtentDistance(1.0e-9)

    #expect(rectangularResult?.didMutate == true)
    #expect(radialResult?.didMutate == true)
    #expect(curveResult?.didMutate == true)
    #expect(try rectangularFirstAxisDistance(in: session.document, sourceID: rectangularSourceID) == minimumDistance)
    #expect(try radialAxisDistance(in: session.document, sourceID: radialSourceID) == minimumDistance)
    #expect(try curveExtentDistance(in: session.document, sourceID: curveSourceID) == minimumDistance)
}

@MainActor
@Test func patternArrayEditingServiceNormalizesRadialAngleToPlannerTolerance() async throws {
    let session = EditorSession()
    _ = try #require(session.createDefaultExtrudedRectangle())
    let sourceID = try createPatternArray(
        in: session,
        name: "Minimum Radial Angle Array",
        distribution: .radial(RadialPatternArray(
            angularAxis: PatternArrayAngularAxis(
                center: .origin,
                axis: .unitZ,
                angle: .angle(90.0, .degree),
                copyCount: 3,
                angleMode: .spacing
            )
        ))
    )

    let result = PatternArrayEditingService(
        session: session,
        sourceID: sourceID
    ).setRadialAngle(degrees: 1.0e-12)

    let source = try #require(session.document.productMetadata.patternArrays[sourceID])
    guard case .radial(let radial) = source.distribution,
          case .constant(let quantity) = radial.angularAxis.angle else {
        Issue.record("Expected a radial pattern source with a constant angular distance.")
        return
    }
    #expect(result?.didMutate == true)
    #expect(radial.angularAxis.angleMode == .spacing)
    #expect(quantity.kind == .angle)
    #expect(quantity.value == PatternArrayAnglePolicy.standard.minimumAngleRadians)
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
@Test func patternArrayEditingServiceMovesPolylineCurvePathPoint() async throws {
    let session = EditorSession()
    _ = try #require(session.createDefaultExtrudedRectangle())
    let sourceID = try createPatternArray(
        in: session,
        name: "Editable Polyline Curve Path",
        distribution: .curve(CurvePatternArray(
            path: .polyline(
                points: [
                    .origin,
                    Point3D(x: 0.03, y: 0.0, z: 0.0),
                    Point3D(x: 0.06, y: 0.0, z: 0.0),
                ],
                normal: .unitZ
            ),
            copyCount: 2
        ))
    )

    let result = PatternArrayEditingService(
        session: session,
        sourceID: sourceID
    ).setCurvePathPoint(
        index: 1,
        point: Point3D(x: 0.03, y: 0.01, z: 0.02)
    )

    let source = try #require(session.document.productMetadata.patternArrays[sourceID])
    guard case .curve(let curve) = source.distribution,
          case .polyline(let points, let normal) = curve.path else {
        Issue.record("Expected an editable polyline Curve Pattern Array.")
        return
    }
    #expect(result?.didMutate == true)
    #expect(points[0] == .origin)
    #expect(points[1] == Point3D(x: 0.03, y: 0.01, z: 0.02))
    #expect(points[2] == Point3D(x: 0.06, y: 0.0, z: 0.0))
    #expect(normal == .unitZ)
}

@MainActor
@Test func patternArrayEditingServiceRejectsOutOfRangePolylinePointMove() async throws {
    let session = EditorSession()
    _ = try #require(session.createDefaultExtrudedRectangle())
    let sourceID = try createPatternArray(
        in: session,
        name: "Out Of Range Polyline Curve Path",
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

    let result = PatternArrayEditingService(
        session: session,
        sourceID: sourceID
    ).setCurvePathPoint(
        index: 3,
        point: Point3D(x: 0.03, y: 0.01, z: 0.02)
    )

    let source = try #require(session.document.productMetadata.patternArrays[sourceID])
    guard case .curve(let curve) = source.distribution,
          case .polyline(let points, _) = curve.path else {
        Issue.record("Expected an editable polyline Curve Pattern Array.")
        return
    }
    #expect(result == nil)
    #expect(points == [
        .origin,
        Point3D(x: 0.03, y: 0.0, z: 0.0),
    ])
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

private func rectangularFirstAxisDistance(
    in document: DesignDocument,
    sourceID: PatternArraySourceID
) throws -> Double {
    let source = try #require(document.productMetadata.patternArrays[sourceID])
    guard case .rectangular(let rectangular) = source.distribution,
          case .constant(let quantity) = rectangular.firstAxis.distance,
          quantity.kind == .length else {
        throw EditorError(
            code: .referenceUnresolved,
            message: "Expected a rectangular pattern source with a constant linear axis distance."
        )
    }
    return quantity.value
}

private func radialAxisDistance(
    in document: DesignDocument,
    sourceID: PatternArraySourceID
) throws -> Double {
    let source = try #require(document.productMetadata.patternArrays[sourceID])
    guard case .radial(let radial) = source.distribution,
          let radialAxis = radial.radialAxis,
          case .constant(let quantity) = radialAxis.distance,
          quantity.kind == .length else {
        throw EditorError(
            code: .referenceUnresolved,
            message: "Expected a radial pattern source with a constant linear axis distance."
        )
    }
    return quantity.value
}

private func curveExtentDistance(
    in document: DesignDocument,
    sourceID: PatternArraySourceID
) throws -> Double {
    let source = try #require(document.productMetadata.patternArrays[sourceID])
    guard case .curve(let curve) = source.distribution,
          case .constant(let quantity) = curve.extent,
          quantity.kind == .length else {
        throw EditorError(
            code: .referenceUnresolved,
            message: "Expected a curve pattern source with a constant linear extent."
        )
    }
    return quantity.value
}

private func parameterQuantity(
    named name: String,
    in document: DesignDocument
) throws -> Quantity {
    let parameter = try #require(document.cadDocument.parameters.parameters.values.first { $0.name == name })
    guard case .constant(let quantity) = parameter.expression else {
        throw EditorError(
            code: .referenceUnresolved,
            message: "Expected a constant parameter expression."
        )
    }
    return quantity
}
