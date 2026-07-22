import Foundation
import Testing
import SwiftCAD
@testable import RupaCore

@Test func createBridgeCurveAddsTangentConstrainedSplineBetweenLineEndpoints() throws {
    let setup = try bridgeCurveTwoLineDocument()
    var document = setup.document

    let bridgeID = try document.createBridgeCurve(
        featureID: setup.featureID,
        firstEndpoint: BridgeCurveEndpoint(
            reference: .lineEnd(setup.firstLineID)
        ),
        secondEndpoint: BridgeCurveEndpoint(
            reference: .lineStart(setup.secondLineID)
        ),
        continuity: .g1
    )

    let sketch = try #require(bridgeCurveSketch(in: document, featureID: setup.featureID))
    let bridgeEntity = try #require(sketch.entities[bridgeID])
    let source = try #require(document.productMetadata.bridgeCurveSources.values.first)
    guard case .spline(let spline) = bridgeEntity else {
        Issue.record("Bridge curve should create a spline entity.")
        return
    }
    #expect(source.featureID == setup.featureID)
    #expect(source.entityID == bridgeID)
    #expect(source.firstEndpoint.reference == .lineEnd(setup.firstLineID))
    #expect(source.secondEndpoint.reference == .lineStart(setup.secondLineID))
    #expect(source.continuity == .g1)
    #expect(spline.controlPoints.count == 7)
    #expect(sketch.constraints.contains(.coincident(
        .splineControlPoint(entity: bridgeID, index: 0),
        .lineEnd(setup.firstLineID)
    )))
    #expect(sketch.constraints.contains(.coincident(
        .splineControlPoint(entity: bridgeID, index: 6),
        .lineStart(setup.secondLineID)
    )))
    #expect(sketch.constraints.contains(.splineEndpointTangent(
        SketchSplineLineTangencyConstraint(
            splineEndpoint: SketchSplineEndpointReference(splineID: bridgeID, endpoint: .start),
            line: setup.firstLineID,
            orientation: .aligned
        )
    )))
    #expect(sketch.constraints.contains(.splineEndpointTangent(
        SketchSplineLineTangencyConstraint(
            splineEndpoint: SketchSplineEndpointReference(splineID: bridgeID, endpoint: .end),
            line: setup.secondLineID,
            orientation: .aligned
        )
    )))

    let analysis = try CurveAnalysisService(samplesPerSegment: 8).analyze(
        document: document,
        featureID: setup.featureID,
        entityID: bridgeID,
        displayUnit: .millimeter
    )
    #expect(analysis.counts.curveCount == 1)
    #expect(analysis.counts.continuityJoinCount == 3)
    #expect(analysis.curves.first?.curveKind == .spline)
    #expect(analysis.continuityJoins.filter { $0.joinKind == .constrainedEndpoint }.count == 2)
    #expect(analysis.continuityJoins.filter { $0.joinKind == .internalSplineKnot }.count == 1)
}

@Test func bridgeCurveEndpointSelectionResolverResolvesSelectedLineEndpoint() throws {
    let setup = try bridgeCurveTwoLineDocument()
    let summary = try SketchEntitySnapshotService().snapshot(document: setup.document)
    let firstLine = try #require(summary.entries.first { $0.entityID == setup.firstLineID.description })
    let lineEnd = try #require(firstLine.pointHandles.first { $0.handle == .lineEnd })
    let sceneNodeID = try #require(firstLine.sceneNodeID.flatMap(UUID.init(uuidString:)))
    let target = SelectionTarget(
        sceneNodeID: SceneNodeID(sceneNodeID),
        component: .sketchEntity(SelectionComponentID(rawValue: lineEnd.selectionComponentID))
    )

    let endpoint = try #require(
        try BridgeCurveEndpointSelectionResolver().endpoint(for: target, in: setup.document)
    )

    #expect(endpoint.reference == .lineEnd(setup.firstLineID))
    #expect(endpoint.parameter == nil)
    #expect(endpoint.reversesSense == false)
}

@Test func bridgeCurveEndpointHandleServiceResolvesSelectedBridgeSourceEndpoints() throws {
    let setup = try bridgeCurveTwoLineDocument()
    var document = setup.document
    let bridgeID = try document.createBridgeCurve(
        featureID: setup.featureID,
        firstEndpoint: BridgeCurveEndpoint(reference: .lineEnd(setup.firstLineID)),
        secondEndpoint: BridgeCurveEndpoint(reference: .lineStart(setup.secondLineID)),
        continuity: .g1
    )
    let source = try #require(document.productMetadata.bridgeCurveSources.values.first)
    let summary = try SketchEntitySnapshotService().snapshot(document: document)
    let bridgeEntry = try #require(summary.entries.first { $0.entityID == bridgeID.description })
    let selectedTarget = try #require(bridgeEntry.selectionTarget())

    let handles = try BridgeCurveEndpointHandleService().handles(
        for: SelectionModel(selectedTargets: [selectedTarget]),
        in: document
    )

    #expect(handles.map(\.role) == [.first, .second])
    #expect(handles.allSatisfy { $0.sourceID == source.id })
    #expect(handles.allSatisfy { $0.bridgeEntityID == bridgeID })
    #expect(handles[0].endpoint.reference == .lineEnd(setup.firstLineID))
    #expect(handles[1].endpoint.reference == .lineStart(setup.secondLineID))
    #expect(bridgeCurveNearlyEqual(handles[0].point.x, 0.003))
    #expect(bridgeCurveNearlyEqual(handles[0].point.y, 0.0))
    #expect(bridgeCurveNearlyEqual(handles[1].point.x, 0.006))
    #expect(bridgeCurveNearlyEqual(handles[1].point.y, 0.003))
    #expect(handles[0].pointReference == .lineEnd(setup.firstLineID))
    #expect(handles[1].pointReference == .lineStart(setup.secondLineID))
}

@Test func bridgeCurveEndpointParameterProjectionProjectsLineParameter() throws {
    let setup = try bridgeCurveTwoLineDocument()

    let projection = try BridgeCurveEndpointParameterProjectionService().projection(
        for: BridgeCurveEndpoint(reference: .lineEnd(setup.firstLineID)),
        featureID: setup.featureID,
        near: Point2D(x: 0.0015, y: 0.0004),
        in: setup.document
    )

    #expect(bridgeCurveNearlyEqual(projection.parameter, 0.5))
    #expect(projection.endpoint.reference == .lineEnd(setup.firstLineID))
    #expect(projection.endpoint.parameter == .scalar(0.5))
    #expect(bridgeCurveNearlyEqual(projection.point.x, 0.0015))
    #expect(bridgeCurveNearlyEqual(projection.point.y, 0.0))
}

@Test func bridgeCurveEndpointParameterProjectionProjectsArcParameter() throws {
    let setup = try bridgeCurveLineArcDocument()
    let radius = 0.002
    let angle = Double.pi / 4.0

    let projection = try BridgeCurveEndpointParameterProjectionService().projection(
        for: BridgeCurveEndpoint(reference: .arcStart(setup.arcID)),
        featureID: setup.featureID,
        near: Point2D(
            x: 0.006 + cos(angle) * radius,
            y: 0.003 + sin(angle) * radius
        ),
        in: setup.document
    )

    #expect(bridgeCurveNearlyEqual(projection.parameter, 0.5))
    #expect(projection.endpoint.reference == .arcStart(setup.arcID))
    #expect(projection.endpoint.parameter == .scalar(0.5))
    #expect(bridgeCurveNearlyEqual(projection.point.x, 0.006 + cos(angle) * radius))
    #expect(bridgeCurveNearlyEqual(projection.point.y, 0.003 + sin(angle) * radius))
}

@Test func bridgeCurveEndpointParameterProjectionClampsArcToNearestEndpointOutsideSpan() throws {
    let setup = try bridgeCurveLineArcDocument()
    let radius = 0.002
    let beforeStartAngle = -Double.pi / 4.0
    let afterEndAngle = Double.pi

    let startProjection = try BridgeCurveEndpointParameterProjectionService().projection(
        for: BridgeCurveEndpoint(reference: .arcStart(setup.arcID)),
        featureID: setup.featureID,
        near: Point2D(
            x: 0.006 + cos(beforeStartAngle) * radius,
            y: 0.003 + sin(beforeStartAngle) * radius
        ),
        in: setup.document
    )
    let endProjection = try BridgeCurveEndpointParameterProjectionService().projection(
        for: BridgeCurveEndpoint(reference: .arcStart(setup.arcID)),
        featureID: setup.featureID,
        near: Point2D(
            x: 0.006 + cos(afterEndAngle) * radius,
            y: 0.003 + sin(afterEndAngle) * radius
        ),
        in: setup.document
    )

    #expect(bridgeCurveNearlyEqual(startProjection.parameter, 0.0))
    #expect(bridgeCurveNearlyEqual(endProjection.parameter, 1.0))
}

@Test func bridgeCurveEndpointParameterProjectionProjectsSplineParameter() throws {
    let setup = try bridgeCurveTwoSplineDocument()

    let projection = try BridgeCurveEndpointParameterProjectionService().projection(
        for: BridgeCurveEndpoint(reference: .splineControlPoint(entity: setup.firstSplineID, index: 3)),
        featureID: setup.featureID,
        near: Point2D(x: 0.00225, y: 0.0005),
        in: setup.document
    )

    #expect(bridgeCurveNearlyEqual(projection.parameter, 0.75, tolerance: 1.0e-8))
    #expect(projection.endpoint.reference == .splineControlPoint(entity: setup.firstSplineID, index: 3))
    #expect(projection.endpoint.parameter == .scalar(projection.parameter))
    #expect(bridgeCurveNearlyEqual(projection.point.x, 0.00225, tolerance: 1.0e-8))
    #expect(bridgeCurveNearlyEqual(projection.point.y, 0.0, tolerance: 1.0e-8))
}

@Test func bridgeCurveEndpointParameterProjectionPreservesEndpointOptions() throws {
    let setup = try bridgeCurveTwoLineDocument()
    let tension = BridgeCurveTension(
        first: .scalar(0.5),
        second: .scalar(1.25),
        third: .scalar(1.75)
    )

    let projection = try BridgeCurveEndpointParameterProjectionService().projection(
        for: BridgeCurveEndpoint(
            reference: .lineEnd(setup.firstLineID),
            reversesSense: true,
            tension: tension
        ),
        featureID: setup.featureID,
        near: Point2D(x: 0.0015, y: 0.0004),
        in: setup.document
    )

    #expect(projection.endpoint.reference == .lineEnd(setup.firstLineID))
    #expect(projection.endpoint.parameter == .scalar(0.5))
    #expect(projection.endpoint.reversesSense)
    #expect(projection.endpoint.tension == tension)

    let sideProjection = try BridgeCurveEndpointParameterProjectionService().projection(
        for: BridgeCurveEndpoint(
            reference: .lineEnd(setup.firstLineID),
            trimSide: .towardEnd
        ),
        featureID: setup.featureID,
        near: Point2D(x: 0.0015, y: 0.0004),
        in: setup.document
    )

    #expect(sideProjection.endpoint.trimSide == .towardEnd)
}

@Test func bridgeCurveEndpointParameterProjectionResolvesCurrentParameterSources() throws {
    let setup = try bridgeCurveTwoLineDocument()
    var document = setup.document
    try document.upsertParameter(
        name: "bridgeValue",
        expression: .scalar(0.25),
        kind: .scalar
    )
    let bridgeValueID = try #require(document.cadDocument.parameterID(named: "bridgeValue"))
    let service = BridgeCurveEndpointParameterProjectionService()

    let endpointParameter = try service.parameter(
        for: BridgeCurveEndpoint(reference: .lineEnd(setup.firstLineID)),
        featureID: setup.featureID,
        in: document
    )
    let expressionParameter = try service.parameter(
        for: BridgeCurveEndpoint(
            reference: .entity(setup.firstLineID),
            parameter: .parameter(bridgeValueID)
        ),
        featureID: setup.featureID,
        in: document
    )

    #expect(bridgeCurveNearlyEqual(endpointParameter, 1.0))
    #expect(bridgeCurveNearlyEqual(expressionParameter, 0.25))
}

@Test func bridgeCurveEndpointParameterProjectionRejectsEntityWithoutParameter() throws {
    let setup = try bridgeCurveTwoLineDocument()
    var caught: EditorError?

    do {
        _ = try BridgeCurveEndpointParameterProjectionService().parameter(
            for: BridgeCurveEndpoint(reference: .entity(setup.firstLineID)),
            featureID: setup.featureID,
            in: setup.document
        )
    } catch let error as EditorError {
        caught = error
    }

    #expect(caught?.code == .commandInvalid)
}

@Test func createBridgeCurveSupportsParametricLinePositionsWithSense() throws {
    let setup = try bridgeCurveTwoLineDocument()
    var document = setup.document

    let bridgeID = try document.createBridgeCurve(
        featureID: setup.featureID,
        firstEndpoint: BridgeCurveEndpoint(
            reference: .entity(setup.firstLineID),
            parameter: .scalar(0.5),
            reversesSense: true
        ),
        secondEndpoint: BridgeCurveEndpoint(
            reference: .entity(setup.secondLineID),
            parameter: .scalar(0.25)
        ),
        continuity: .g0
    )

    let sketch = try #require(bridgeCurveSketch(in: document, featureID: setup.featureID))
    let source = try #require(document.productMetadata.bridgeCurveSources.values.first)
    let bridgeEntity = try #require(sketch.entities[bridgeID])
    guard case .spline(let spline) = bridgeEntity else {
        Issue.record("Parametric Bridge Curve should create a spline entity.")
        return
    }
    let controlPoints = try spline.controlPoints.map { point in
        try bridgeCurveResolvedPoint(point, in: document)
    }

    #expect(source.firstEndpoint.reference == .entity(setup.firstLineID))
    #expect(source.firstEndpoint.parameter == .scalar(0.5))
    #expect(source.firstEndpoint.reversesSense)
    #expect(source.secondEndpoint.reference == .entity(setup.secondLineID))
    #expect(source.secondEndpoint.parameter == .scalar(0.25))
    #expect(sketch.constraints.isEmpty)
    #expect(controlPoints.count == 7)
    #expect(bridgeCurveNearlyEqual(controlPoints[0].x, 0.0015))
    #expect(bridgeCurveNearlyEqual(controlPoints[0].y, 0.0))
    #expect(bridgeCurveNearlyEqual(controlPoints[1].x, 0.0005237187905116682))
    #expect(bridgeCurveNearlyEqual(controlPoints[1].y, 0.0))
    #expect(bridgeCurveNearlyEqual(controlPoints[6].x, 0.006))
    #expect(bridgeCurveNearlyEqual(controlPoints[6].y, 0.00375))
}

@Test func createBridgeCurveRejectsParametricG1WithoutPersistentEndpointConstraint() throws {
    let setup = try bridgeCurveTwoLineDocument()
    var document = setup.document

    do {
        try document.createBridgeCurve(
            featureID: setup.featureID,
            firstEndpoint: BridgeCurveEndpoint(
                reference: .entity(setup.firstLineID),
                parameter: .scalar(0.5)
            ),
            secondEndpoint: BridgeCurveEndpoint(
                reference: .lineStart(setup.secondLineID)
            ),
            continuity: .g1
        )
        Issue.record("Parametric Bridge Curve G1 must fail until a persistent point-on-curve tangent constraint exists.")
    } catch let error as EditorError {
        #expect(error.code == .commandInvalid)
        #expect(error.message.contains("G1"))
    }

    let sketch = try #require(bridgeCurveSketch(in: document, featureID: setup.featureID))
    #expect(sketch.entities.count == 2)
    #expect(document.productMetadata.bridgeCurveSources.isEmpty)
}

@Test func createBridgeCurveTrimsParametricLineSourcesAndAllowsG1() throws {
    let setup = try bridgeCurveTwoLineDocument()
    var document = setup.document

    let bridgeID = try document.createBridgeCurve(
        featureID: setup.featureID,
        firstEndpoint: BridgeCurveEndpoint(
            reference: .entity(setup.firstLineID),
            parameter: .scalar(0.5)
        ),
        secondEndpoint: BridgeCurveEndpoint(
            reference: .entity(setup.secondLineID),
            parameter: .scalar(0.25),
            reversesSense: true,
            trimSide: .towardEnd
        ),
        continuity: .g1,
        trimsSourceCurves: true
    )

    let sketch = try #require(bridgeCurveSketch(in: document, featureID: setup.featureID))
    let source = try #require(document.productMetadata.bridgeCurveSources.values.first)
    let firstLine = try #require(bridgeCurveLine(setup.firstLineID, in: sketch))
    let secondLine = try #require(bridgeCurveLine(setup.secondLineID, in: sketch))
    let firstStart = try bridgeCurveResolvedPoint(firstLine.start, in: document)
    let firstEnd = try bridgeCurveResolvedPoint(firstLine.end, in: document)
    let secondStart = try bridgeCurveResolvedPoint(secondLine.start, in: document)
    let secondEnd = try bridgeCurveResolvedPoint(secondLine.end, in: document)

    #expect(source.trimsSourceCurves)
    #expect(source.firstEndpoint.reference == .lineEnd(setup.firstLineID))
    #expect(source.firstEndpoint.parameter == nil)
    #expect(source.firstEndpoint.trimSide == .towardStart)
    #expect(source.secondEndpoint.reference == .lineStart(setup.secondLineID))
    #expect(source.secondEndpoint.parameter == nil)
    #expect(source.secondEndpoint.reversesSense == false)
    #expect(source.secondEndpoint.trimSide == .towardEnd)
    #expect(bridgeCurveNearlyEqual(firstStart.x, 0.0))
    #expect(bridgeCurveNearlyEqual(firstEnd.x, 0.0015))
    #expect(bridgeCurveNearlyEqual(secondStart.y, 0.00375))
    #expect(bridgeCurveNearlyEqual(secondEnd.y, 0.006))
    #expect(sketch.constraints.contains(.coincident(
        .splineControlPoint(entity: bridgeID, index: 0),
        .lineEnd(setup.firstLineID)
    )))
    #expect(sketch.constraints.contains(.coincident(
        .splineControlPoint(entity: bridgeID, index: 6),
        .lineStart(setup.secondLineID)
    )))
    #expect(sketch.constraints.contains(.splineEndpointTangent(
        SketchSplineLineTangencyConstraint(
            splineEndpoint: SketchSplineEndpointReference(splineID: bridgeID, endpoint: .start),
            line: setup.firstLineID,
            orientation: .aligned
        )
    )))
    #expect(sketch.constraints.contains(.splineEndpointTangent(
        SketchSplineLineTangencyConstraint(
            splineEndpoint: SketchSplineEndpointReference(splineID: bridgeID, endpoint: .end),
            line: setup.secondLineID,
            orientation: .aligned
        )
    )))
}

@Test func createBridgeCurveTrimSideIsIndependentFromSense() throws {
    let startSideSetup = try bridgeCurveTwoLineDocument()
    var startSideDocument = startSideSetup.document

    let startSideBridgeID = try startSideDocument.createBridgeCurve(
        featureID: startSideSetup.featureID,
        firstEndpoint: BridgeCurveEndpoint(
            reference: .entity(startSideSetup.firstLineID),
            parameter: .scalar(0.5),
            reversesSense: true,
            trimSide: .towardStart
        ),
        secondEndpoint: BridgeCurveEndpoint(
            reference: .lineStart(startSideSetup.secondLineID)
        ),
        continuity: .g0,
        trimsSourceCurves: true
    )

    let startSideSketch = try #require(bridgeCurveSketch(in: startSideDocument, featureID: startSideSetup.featureID))
    let startSideSource = try #require(startSideDocument.productMetadata.bridgeCurveSources.values.first)
    let startSideLine = try #require(bridgeCurveLine(startSideSetup.firstLineID, in: startSideSketch))
    let startSideLineStart = try bridgeCurveResolvedPoint(startSideLine.start, in: startSideDocument)
    let startSideLineEnd = try bridgeCurveResolvedPoint(startSideLine.end, in: startSideDocument)
    let startSideBridgeEntity = try #require(startSideSketch.entities[startSideBridgeID])
    guard case .spline(let startSideSpline) = startSideBridgeEntity else {
        Issue.record("Bridge curve should remain a spline after start-side trim.")
        return
    }
    let startSideControlPoints = try startSideSpline.controlPoints.map { point in
        try bridgeCurveResolvedPoint(point, in: startSideDocument)
    }

    #expect(startSideSource.firstEndpoint.reference == .lineEnd(startSideSetup.firstLineID))
    #expect(startSideSource.firstEndpoint.reversesSense)
    #expect(startSideSource.firstEndpoint.trimSide == .towardStart)
    #expect(bridgeCurveNearlyEqual(startSideLineStart.x, 0.0))
    #expect(bridgeCurveNearlyEqual(startSideLineEnd.x, 0.0015))
    #expect(startSideControlPoints[1].x < startSideControlPoints[0].x)

    let endSideSetup = try bridgeCurveTwoLineDocument()
    var endSideDocument = endSideSetup.document

    let endSideBridgeID = try endSideDocument.createBridgeCurve(
        featureID: endSideSetup.featureID,
        firstEndpoint: BridgeCurveEndpoint(
            reference: .entity(endSideSetup.firstLineID),
            parameter: .scalar(0.5),
            trimSide: .towardEnd
        ),
        secondEndpoint: BridgeCurveEndpoint(
            reference: .lineStart(endSideSetup.secondLineID)
        ),
        continuity: .g0,
        trimsSourceCurves: true
    )

    let endSideSketch = try #require(bridgeCurveSketch(in: endSideDocument, featureID: endSideSetup.featureID))
    let endSideSource = try #require(endSideDocument.productMetadata.bridgeCurveSources.values.first)
    let endSideLine = try #require(bridgeCurveLine(endSideSetup.firstLineID, in: endSideSketch))
    let endSideLineStart = try bridgeCurveResolvedPoint(endSideLine.start, in: endSideDocument)
    let endSideLineEnd = try bridgeCurveResolvedPoint(endSideLine.end, in: endSideDocument)
    let endSideBridgeEntity = try #require(endSideSketch.entities[endSideBridgeID])
    guard case .spline(let endSideSpline) = endSideBridgeEntity else {
        Issue.record("Bridge curve should remain a spline after end-side trim.")
        return
    }
    let endSideControlPoints = try endSideSpline.controlPoints.map { point in
        try bridgeCurveResolvedPoint(point, in: endSideDocument)
    }

    #expect(endSideSource.firstEndpoint.reference == .lineStart(endSideSetup.firstLineID))
    #expect(endSideSource.firstEndpoint.reversesSense)
    #expect(endSideSource.firstEndpoint.trimSide == .towardEnd)
    #expect(bridgeCurveNearlyEqual(endSideLineStart.x, 0.0015))
    #expect(bridgeCurveNearlyEqual(endSideLineEnd.x, 0.003))
    #expect(endSideControlPoints[1].x > endSideControlPoints[0].x)
}

@Test func createBridgeCurveAddsSmoothConstraintsBetweenSplineEndpoints() throws {
    let setup = try bridgeCurveTwoSplineDocument()
    var document = setup.document

    let bridgeID = try document.createBridgeCurve(
        featureID: setup.featureID,
        firstEndpoint: BridgeCurveEndpoint(
            reference: .splineControlPoint(entity: setup.firstSplineID, index: 3)
        ),
        secondEndpoint: BridgeCurveEndpoint(
            reference: .splineControlPoint(entity: setup.secondSplineID, index: 0)
        ),
        continuity: .g2
    )

    let sketch = try #require(bridgeCurveSketch(in: document, featureID: setup.featureID))
    let source = try #require(document.productMetadata.bridgeCurveSources.values.first)
    #expect(source.featureID == setup.featureID)
    #expect(source.entityID == bridgeID)
    #expect(source.continuity == .g2)
    #expect(sketch.constraints.contains(.smoothSplineEndpoints(
        SketchSplineEndpointTangencyConstraint(
            first: SketchSplineEndpointReference(splineID: bridgeID, endpoint: .start),
            second: SketchSplineEndpointReference(splineID: setup.firstSplineID, endpoint: .end),
            orientation: .aligned
        )
    )))
    #expect(sketch.constraints.contains(.smoothSplineEndpoints(
        SketchSplineEndpointTangencyConstraint(
            first: SketchSplineEndpointReference(splineID: bridgeID, endpoint: .end),
            second: SketchSplineEndpointReference(splineID: setup.secondSplineID, endpoint: .start),
            orientation: .aligned
        )
    )))

    let analysis = try CurveAnalysisService(samplesPerSegment: 8).analyze(
        document: document,
        featureID: setup.featureID,
        entityID: bridgeID,
        displayUnit: .millimeter
    )
    #expect(analysis.counts.curveCount == 1)
    #expect(analysis.counts.continuityJoinCount == 3)
    let constrainedJoins = analysis.continuityJoins.filter { $0.joinKind == .constrainedEndpoint }
    #expect(constrainedJoins.count == 2)
    #expect(constrainedJoins.allSatisfy { $0.requiredContinuity == .g2 })
    #expect(analysis.continuityJoins.filter { $0.joinKind == .internalSplineKnot }.count == 1)
}

@Test func bridgeCurveSourceValidationRejectsBrokenGeneratedEntity() throws {
    let setup = try bridgeCurveTwoLineDocument()
    var document = setup.document

    let bridgeID = try document.createBridgeCurve(
        featureID: setup.featureID,
        firstEndpoint: BridgeCurveEndpoint(
            reference: .lineEnd(setup.firstLineID)
        ),
        secondEndpoint: BridgeCurveEndpoint(
            reference: .lineStart(setup.secondLineID)
        ),
        continuity: .g0
    )

    guard var feature = document.cadDocument.designGraph.nodes[setup.featureID],
          case var .sketch(sketch) = feature.operation else {
        Issue.record("Bridge curve validation setup requires a sketch feature.")
        return
    }
    sketch.entities.removeValue(forKey: bridgeID)
    feature.operation = .sketch(sketch)
    document.cadDocument.designGraph.nodes[setup.featureID] = feature

    do {
        try document.productMetadata.validate(
            against: document.cadDocument,
            objectRegistry: .builtIn
        )
        Issue.record("Product metadata validation must reject a bridge source with a missing generated spline.")
    } catch {
        #expect(String(describing: error).contains("Bridge curve source entities"))
    }
}

@Test func setBridgeCurveParametersRegeneratesExistingBridgeEntity() throws {
    let setup = try bridgeCurveTwoLineDocument()
    var document = setup.document

    let bridgeID = try document.createBridgeCurve(
        featureID: setup.featureID,
        firstEndpoint: BridgeCurveEndpoint(
            reference: .lineEnd(setup.firstLineID)
        ),
        secondEndpoint: BridgeCurveEndpoint(
            reference: .lineStart(setup.secondLineID)
        ),
        continuity: .g1
    )
    let source = try #require(document.productMetadata.bridgeCurveSources.values.first)

    try document.setBridgeCurveParameters(
        sourceID: source.id,
        firstEndpoint: BridgeCurveEndpoint(
            reference: .lineEnd(setup.firstLineID),
            tension: BridgeCurveTension(
                first: .scalar(1.2),
                second: .scalar(0.8),
                third: .scalar(2.0)
            )
        ),
        secondEndpoint: BridgeCurveEndpoint(
            reference: .lineStart(setup.secondLineID),
            tension: BridgeCurveTension(
                first: .scalar(0.5),
                second: .scalar(1.1),
                third: .scalar(1.0)
            )
        )
    )

    let updatedSource = try #require(document.productMetadata.bridgeCurveSources[source.id])
    let sketch = try #require(bridgeCurveSketch(in: document, featureID: setup.featureID))
    let bridgeEntity = try #require(sketch.entities[bridgeID])
    guard case .spline(let spline) = bridgeEntity else {
        Issue.record("Updated bridge curve should remain a spline entity.")
        return
    }
    let controlPoints = try spline.controlPoints.map { point in
        try bridgeCurveResolvedPoint(point, in: document)
    }
    #expect(updatedSource.entityID == bridgeID)
    #expect(updatedSource.continuity == .g1)
    #expect(controlPoints.count == 7)
    #expect(bridgeCurveNearlyEqual(controlPoints[1].x, 0.003848528137423857))
    #expect(bridgeCurveNearlyEqual(controlPoints[1].y, 0.0))
    #expect(bridgeCurveNearlyEqual(controlPoints[2].x, 0.0046))
    #expect(bridgeCurveNearlyEqual(controlPoints[2].y, 0.0016))
    #expect(bridgeCurveNearlyEqual(controlPoints[3].x, 0.005))
    #expect(bridgeCurveNearlyEqual(controlPoints[3].y, 0.002))
    #expect(bridgeCurveNearlyEqual(controlPoints[4].x, 0.00555))
    #expect(bridgeCurveNearlyEqual(controlPoints[4].y, 0.00255))
    #expect(bridgeCurveNearlyEqual(controlPoints[5].x, 0.006))
    #expect(bridgeCurveNearlyEqual(controlPoints[5].y, 0.002646446609406726))
    #expect(sketch.constraints.contains(.splineEndpointTangent(
        SketchSplineLineTangencyConstraint(
            splineEndpoint: SketchSplineEndpointReference(splineID: bridgeID, endpoint: .start),
            line: setup.firstLineID,
            orientation: .aligned
        )
    )))
    #expect(sketch.constraints.contains(.splineEndpointTangent(
        SketchSplineLineTangencyConstraint(
            splineEndpoint: SketchSplineEndpointReference(splineID: bridgeID, endpoint: .end),
            line: setup.secondLineID,
            orientation: .aligned
        )
    )))
}

@Test func setBridgeCurveParametersRejectsBridgeSelfReference() throws {
    let setup = try bridgeCurveTwoLineDocument()
    var document = setup.document

    let bridgeID = try document.createBridgeCurve(
        featureID: setup.featureID,
        firstEndpoint: BridgeCurveEndpoint(
            reference: .lineEnd(setup.firstLineID)
        ),
        secondEndpoint: BridgeCurveEndpoint(
            reference: .lineStart(setup.secondLineID)
        ),
        continuity: .g1
    )
    let source = try #require(document.productMetadata.bridgeCurveSources.values.first)

    do {
        try document.setBridgeCurveParameters(
            sourceID: source.id,
            firstEndpoint: BridgeCurveEndpoint(
                reference: .splineControlPoint(entity: bridgeID, index: 0)
            )
        )
        Issue.record("Bridge curve parameter update must reject endpoint references to its generated spline.")
    } catch let error as EditorError {
        #expect(error.code == .commandInvalid)
        #expect(error.message.contains("generated bridge spline"))
    }

    let sketch = try #require(bridgeCurveSketch(in: document, featureID: setup.featureID))
    #expect(sketch.entities[bridgeID] != nil)
}

@Test func createBridgeCurveRejectsArcTangencyWithoutPersistentConstraint() throws {
    let setup = try bridgeCurveLineArcDocument()
    var document = setup.document

    do {
        try document.createBridgeCurve(
            featureID: setup.featureID,
            firstEndpoint: BridgeCurveEndpoint(
                reference: .lineEnd(setup.lineID)
            ),
            secondEndpoint: BridgeCurveEndpoint(
                reference: .arcStart(setup.arcID)
            ),
            continuity: .g1
        )
        Issue.record("Bridge curve tangency to arcs must fail until a persistent arc endpoint tangent constraint exists.")
    } catch let error as EditorError {
        #expect(error.code == .commandInvalid)
        #expect(error.message.contains("G1"))
    }

    let sketch = try #require(bridgeCurveSketch(in: document, featureID: setup.featureID))
    #expect(sketch.entities.count == 2)
    #expect(document.productMetadata.bridgeCurveSources.isEmpty)
}

@Test func createBridgeCurveSupportsDifferentEndpointContinuityLevels() throws {
    let setup = try bridgeCurveTwoSplineDocument()
    var document = setup.document

    let bridgeID = try document.createBridgeCurve(
        featureID: setup.featureID,
        firstEndpoint: BridgeCurveEndpoint(
            reference: .splineControlPoint(entity: setup.firstSplineID, index: 3)
        ),
        secondEndpoint: BridgeCurveEndpoint(
            reference: .splineControlPoint(entity: setup.secondSplineID, index: 0)
        ),
        continuity: BridgeCurveContinuity(first: .g2, second: .g1)
    )

    let sketch = try #require(bridgeCurveSketch(in: document, featureID: setup.featureID))
    let source = try #require(document.productMetadata.bridgeCurveSources.values.first)
    #expect(source.entityID == bridgeID)
    #expect(source.continuity == BridgeCurveContinuity(first: .g2, second: .g1))
    #expect(sketch.constraints.contains(.smoothSplineEndpoints(
        SketchSplineEndpointTangencyConstraint(
            first: SketchSplineEndpointReference(splineID: bridgeID, endpoint: .start),
            second: SketchSplineEndpointReference(splineID: setup.firstSplineID, endpoint: .end),
            orientation: .aligned
        )
    )))
    #expect(sketch.constraints.contains(.tangentSplineEndpoints(
        SketchSplineEndpointTangencyConstraint(
            first: SketchSplineEndpointReference(splineID: bridgeID, endpoint: .end),
            second: SketchSplineEndpointReference(splineID: setup.secondSplineID, endpoint: .start),
            orientation: .aligned
        )
    )))
    #expect(sketch.constraints.contains(.smoothSplineEndpoints(
        SketchSplineEndpointTangencyConstraint(
            first: SketchSplineEndpointReference(splineID: bridgeID, endpoint: .end),
            second: SketchSplineEndpointReference(splineID: setup.secondSplineID, endpoint: .start),
            orientation: .aligned
        )
    )) == false)
}

@Test func createBridgeCurveRejectsG3BeforeMutation() throws {
    let setup = try bridgeCurveTwoSplineDocument()
    var document = setup.document

    do {
        try document.createBridgeCurve(
            featureID: setup.featureID,
            firstEndpoint: BridgeCurveEndpoint(
                reference: .splineControlPoint(entity: setup.firstSplineID, index: 3)
            ),
            secondEndpoint: BridgeCurveEndpoint(
                reference: .splineControlPoint(entity: setup.secondSplineID, index: 0)
            ),
            continuity: BridgeCurveContinuity(first: .g3, second: .g2)
        )
        Issue.record("Bridge Curve must reject G3 until a persistent G3 constraint exists.")
    } catch let error as EditorError {
        #expect(error.code == .commandInvalid)
        #expect(error.message.contains("G3"))
    }

    let sketch = try #require(bridgeCurveSketch(in: document, featureID: setup.featureID))
    #expect(sketch.entities.count == 2)
    #expect(document.productMetadata.bridgeCurveSources.isEmpty)
}

private func bridgeCurveTwoLineDocument() throws -> (
    document: DesignDocument,
    featureID: FeatureID,
    firstLineID: SketchEntityID,
    secondLineID: SketchEntityID
) {
    var document = DesignDocument.empty()
    let featureID = try document.createLineSketch(
        name: "Bridge Line Source",
        plane: .xy,
        start: bridgeCurvePoint(x: 0.0, y: 0.0),
        end: bridgeCurvePoint(x: 0.003, y: 0.0)
    )
    guard var feature = document.cadDocument.designGraph.nodes[featureID],
          case var .sketch(sketch) = feature.operation,
          let firstLineID = sketch.entities.keys.first else {
        throw EditorError(
            code: .referenceUnresolved,
            message: "Bridge curve line setup requires a line sketch."
        )
    }
    let secondLineID = SketchEntityID()
    sketch.entities[secondLineID] = .line(
        SketchLine(
            start: bridgeCurvePoint(x: 0.006, y: 0.003),
            end: bridgeCurvePoint(x: 0.006, y: 0.006)
        )
    )
    feature.operation = .sketch(sketch)
    document.cadDocument.designGraph.nodes[featureID] = feature
    document.cadDocument.designGraph.revision = document.cadDocument.designGraph.revision.advanced()
    return (document, featureID, firstLineID, secondLineID)
}

private func bridgeCurveTwoSplineDocument() throws -> (
    document: DesignDocument,
    featureID: FeatureID,
    firstSplineID: SketchEntityID,
    secondSplineID: SketchEntityID
) {
    var document = DesignDocument.empty()
    let featureID = try document.createSplineSketch(
        name: "Bridge Spline Source",
        plane: .xy,
        spline: SketchSpline(controlPoints: [
            bridgeCurvePoint(x: 0.000, y: 0.000),
            bridgeCurvePoint(x: 0.001, y: 0.000),
            bridgeCurvePoint(x: 0.002, y: 0.000),
            bridgeCurvePoint(x: 0.003, y: 0.000),
        ])
    )
    guard var feature = document.cadDocument.designGraph.nodes[featureID],
          case var .sketch(sketch) = feature.operation,
          let firstSplineID = sketch.entities.keys.first else {
        throw EditorError(
            code: .referenceUnresolved,
            message: "Bridge curve spline setup requires a spline sketch."
        )
    }
    let secondSplineID = SketchEntityID()
    sketch.entities[secondSplineID] = .spline(
        SketchSpline(controlPoints: [
            bridgeCurvePoint(x: 0.006, y: 0.003),
            bridgeCurvePoint(x: 0.007, y: 0.003),
            bridgeCurvePoint(x: 0.008, y: 0.003),
            bridgeCurvePoint(x: 0.009, y: 0.003),
        ])
    )
    feature.operation = .sketch(sketch)
    document.cadDocument.designGraph.nodes[featureID] = feature
    document.cadDocument.designGraph.revision = document.cadDocument.designGraph.revision.advanced()
    return (document, featureID, firstSplineID, secondSplineID)
}

private func bridgeCurveLineArcDocument() throws -> (
    document: DesignDocument,
    featureID: FeatureID,
    lineID: SketchEntityID,
    arcID: SketchEntityID
) {
    var document = DesignDocument.empty()
    let featureID = try document.createLineSketch(
        name: "Bridge Line Arc Source",
        plane: .xy,
        start: bridgeCurvePoint(x: 0.000, y: 0.000),
        end: bridgeCurvePoint(x: 0.003, y: 0.000)
    )
    guard var feature = document.cadDocument.designGraph.nodes[featureID],
          case var .sketch(sketch) = feature.operation,
          let lineID = sketch.entities.keys.first else {
        throw EditorError(
            code: .referenceUnresolved,
            message: "Bridge curve line-arc setup requires a line sketch."
        )
    }
    let arcID = SketchEntityID()
    sketch.entities[arcID] = .arc(
        SketchArc(
            center: bridgeCurvePoint(x: 0.006, y: 0.003),
            radius: .length(0.002, .meter),
            startAngle: .angle(0.0, .radian),
            endAngle: .angle(Double.pi / 2.0, .radian)
        )
    )
    feature.operation = .sketch(sketch)
    document.cadDocument.designGraph.nodes[featureID] = feature
    document.cadDocument.designGraph.revision = document.cadDocument.designGraph.revision.advanced()
    return (document, featureID, lineID, arcID)
}

private func bridgeCurveSketch(
    in document: DesignDocument,
    featureID: FeatureID
) -> Sketch? {
    guard let feature = document.cadDocument.designGraph.nodes[featureID],
          case .sketch(let sketch) = feature.operation else {
        return nil
    }
    return sketch
}

private func bridgeCurveLine(
    _ entityID: SketchEntityID,
    in sketch: Sketch
) -> SketchLine? {
    guard case .line(let line) = sketch.entities[entityID] else {
        return nil
    }
    return line
}

private func bridgeCurvePoint(x: Double, y: Double) -> SketchPoint {
    SketchPoint(
        x: .length(x, .meter),
        y: .length(y, .meter)
    )
}

private func bridgeCurveResolvedPoint(
    _ point: SketchPoint,
    in document: DesignDocument
) throws -> (x: Double, y: Double) {
    let x = try document.cadDocument.parameters.resolvedValue(for: point.x)
    let y = try document.cadDocument.parameters.resolvedValue(for: point.y)
    #expect(x.kind == .length)
    #expect(y.kind == .length)
    return (x.value, y.value)
}

private func bridgeCurveNearlyEqual(
    _ lhs: Double,
    _ rhs: Double,
    tolerance: Double = 1.0e-12
) -> Bool {
    abs(lhs - rhs) <= tolerance
}
