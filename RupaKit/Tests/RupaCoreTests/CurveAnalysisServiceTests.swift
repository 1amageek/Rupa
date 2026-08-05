import Foundation
import Testing
import SwiftCAD
@testable import RupaCore

@Test func curveAnalysisServiceReportsSamplesCurvatureAndLength() throws {
    var document = DesignDocument.empty()
    _ = try document.createLineSketch(
        name: "Analysis Line",
        plane: .xy,
        start: curveAnalysisPoint(x: 0.0, y: 0.0),
        end: curveAnalysisPoint(x: 0.010, y: 0.0)
    )
    _ = try document.createCircleSketch(
        name: "Analysis Circle",
        plane: .xy,
        center: curveAnalysisPoint(x: 0.0, y: 0.0),
        radius: .length(0.004, .meter)
    )
    _ = try document.createArcSketch(
        name: "Analysis Arc",
        plane: .xy,
        center: curveAnalysisPoint(x: 0.0, y: 0.0),
        radius: .length(0.006, .meter),
        startAngle: .angle(0.0, .radian),
        endAngle: .angle(Double.pi / 2.0, .radian)
    )
    _ = try document.createSplineSketch(
        name: "Analysis Spline",
        plane: .xy,
        spline: SketchSpline(controlPoints: [
            curveAnalysisPoint(x: 0.0, y: 0.0),
            curveAnalysisPoint(x: 0.002, y: 0.004),
            curveAnalysisPoint(x: 0.006, y: 0.004),
            curveAnalysisPoint(x: 0.008, y: 0.0),
        ])
    )

    let result = try CurveAnalysisService(samplesPerSegment: 16).analyze(document: document, displayUnit: .millimeter)

    #expect(result.displayUnit == .millimeter)
    #expect(result.displayUnitSymbol == "mm")
    #expect(result.counts.curveCount == 4)
    #expect(result.counts.sampleCount > 40)
    let line = try #require(result.curves.first { $0.curveKind == .line })
    let circle = try #require(result.curves.first { $0.curveKind == .circle })
    let arc = try #require(result.curves.first { $0.curveKind == .arc })
    let spline = try #require(result.curves.first { $0.curveKind == .spline })
    #expect(line.samples.count == 2)
    #expect(abs(line.maxAbsCurvature) < 1.0e-12)
    #expect(abs(circle.maxAbsCurvature - 250.0) < 1.0e-9)
    #expect(abs(arc.maxAbsCurvature - (1.0 / 0.006)) < 1.0e-9)
    #expect(abs(line.approximateLengthDisplayValue - 10.0) < 1.0e-12)
    #expect(abs(circle.maxAbsCurvatureDisplayValue - 0.25) < 1.0e-12)
    #expect(abs(arc.maxAbsCurvatureDisplayValue - (1.0 / 6.0)) < 1.0e-12)
    #expect(circle.curvatureDisplayUnitSymbol == "1/mm")
    #expect(spline.samples.count == 17)
    #expect(spline.maxAbsCurvature > 1.0)
    #expect(spline.approximateLength > 0.008)
    let firstSplineSample = try #require(spline.samples.first)
    #expect(abs(firstSplineSample.parameter) < 1.0e-12)
    #expect(spline.pointDisplayScale == 1_000.0)
    #expect(spline.curvatureDisplayScale == 0.001)
    #expect(abs(hypot(firstSplineSample.normal.x, firstSplineSample.normal.y) - 1.0) < 1.0e-12)
}

@Test func curveAnalysisServiceReportsSplineInternalContinuity() throws {
    var document = DesignDocument.empty()
    _ = try document.createSplineSketch(
        name: "Straight G2 Spline",
        plane: .xy,
        spline: SketchSpline(controlPoints: [
            curveAnalysisPoint(x: 0.0, y: 0.0),
            curveAnalysisPoint(x: 0.001, y: 0.0),
            curveAnalysisPoint(x: 0.002, y: 0.0),
            curveAnalysisPoint(x: 0.003, y: 0.0),
            curveAnalysisPoint(x: 0.004, y: 0.0),
            curveAnalysisPoint(x: 0.005, y: 0.0),
            curveAnalysisPoint(x: 0.006, y: 0.0),
        ])
    )

    let result = try CurveAnalysisService(samplesPerSegment: 8).analyze(document: document, displayUnit: .millimeter)

    #expect(result.counts.curveCount == 1)
    #expect(result.counts.continuityJoinCount == 1)
    let join = try #require(result.continuityJoins.first)
    #expect(join.joinKind == .internalSplineKnot)
    #expect(join.constraintKinds == ["splineKnot"])
    #expect(join.requiredContinuity == nil)
    #expect(join.continuity == .g2)
    #expect(join.firstReference == join.secondReference)
    #expect(join.firstReference.contains("splineControlPoint:"))
    #expect(abs(join.positionGap) < 1.0e-12)
    #expect(abs(join.tangentAngle ?? -1.0) < 1.0e-12)
    #expect(abs(join.curvatureGap ?? -1.0) < 1.0e-12)
}

@Test func curveAnalysisServiceReportsConstrainedEndpointG0Continuity() throws {
    let setup = try twoLineCurveAnalysisDocument(
        secondStart: curveAnalysisPoint(x: 0.003, y: 0.0),
        secondEnd: curveAnalysisPoint(x: 0.003, y: 0.004),
        constraint: { firstLineID, secondLineID in
            .coincident(.lineEnd(firstLineID), .lineStart(secondLineID))
        }
    )

    let result = try CurveAnalysisService(samplesPerSegment: 8).analyze(document: setup.document, displayUnit: .millimeter)

    #expect(result.counts.curveCount == 2)
    #expect(result.counts.continuityJoinCount == 1)
    let join = try #require(result.continuityJoins.first)
    #expect(join.joinKind == .constrainedEndpoint)
    #expect(join.constraintKinds == ["coincident"])
    #expect(join.requiredContinuity == .g0)
    #expect(join.firstEntityID == setup.firstLineID.description)
    #expect(join.secondEntityID == setup.secondLineID.description)
    #expect(join.firstReference == "lineEnd:\(setup.firstLineID.description)")
    #expect(join.secondReference == "lineStart:\(setup.secondLineID.description)")
    #expect(join.continuity == .g0)
    #expect(abs(join.positionGap) < 1.0e-12)
    #expect(abs((join.tangentAngle ?? 0.0) - (Double.pi / 2.0)) < 1.0e-12)
    #expect(abs((join.tangentAngleDegrees ?? 0.0) - 90.0) < 1.0e-12)
    #expect(abs(join.curvatureGap ?? -1.0) < 1.0e-12)

    let selectedResult = try CurveAnalysisService(samplesPerSegment: 8).analyze(
        document: setup.document,
        featureID: setup.featureID,
        entityID: setup.firstLineID,
        displayUnit: .millimeter
    )
    #expect(selectedResult.counts.curveCount == 1)
    #expect(selectedResult.counts.continuityJoinCount == 1)
    #expect(selectedResult.curves.first?.entityID == setup.firstLineID.description)
    #expect(selectedResult.continuityJoins.first?.secondEntityID == setup.secondLineID.description)
}

@Test func curveAnalysisServiceAggregatesConstrainedEndpointContinuity() throws {
    let setup = try twoSplineCurveAnalysisDocument()

    let result = try CurveAnalysisService(samplesPerSegment: 8).analyze(document: setup.document, displayUnit: .millimeter)

    #expect(result.counts.curveCount == 2)
    #expect(result.counts.continuityJoinCount == 1)
    let join = try #require(result.continuityJoins.first)
    #expect(join.joinKind == .constrainedEndpoint)
    #expect(join.constraintKinds == ["coincident", "smoothSplineEndpoints"])
    #expect(join.requiredContinuity == .g2)
    #expect(join.firstEntityID == setup.firstSplineID.description)
    #expect(join.secondEntityID == setup.secondSplineID.description)
    #expect(join.firstReference == "splineControlPoint:\(setup.firstSplineID.description):3")
    #expect(join.secondReference == "splineControlPoint:\(setup.secondSplineID.description):0")
    #expect(join.continuity == .g2)
    #expect(abs(join.positionGap) < 1.0e-12)
    #expect(abs(join.tangentAngle ?? -1.0) < 1.0e-12)
    #expect(abs(join.curvatureGap ?? -1.0) < 1.0e-12)
}

@Test func curveAnalysisResultDecodesMissingDisplayValues() throws {
    var document = DesignDocument.empty()
    _ = try document.createLineSketch(
        name: "Legacy Analysis Line",
        plane: .xy,
        start: curveAnalysisPoint(x: 0.0, y: 0.0),
        end: curveAnalysisPoint(x: 0.010, y: 0.0)
    )
    let result = try CurveAnalysisService(samplesPerSegment: 8).analyze(document: document, displayUnit: .millimeter)
    let json = try JSONSerialization.jsonObject(
        with: try JSONEncoder().encode(result)
    ) as? [String: Any]
    var legacyJSON = try #require(json)
    legacyJSON["displayUnitSymbol"] = nil
    var legacyCurve = try #require((legacyJSON["curves"] as? [[String: Any]])?.first)
    legacyCurve["maxAbsCurvatureDisplayValue"] = nil
    legacyCurve["approximateLengthDisplayValue"] = nil
    legacyCurve["displayUnitSymbol"] = nil
    legacyCurve["pointDisplayScale"] = nil
    legacyCurve["curvatureDisplayUnitSymbol"] = nil
    legacyCurve["curvatureDisplayScale"] = nil
    legacyJSON["curves"] = [legacyCurve]

    let decoded = try JSONDecoder().decode(
        CurveAnalysisResult.self,
        from: try JSONSerialization.data(withJSONObject: legacyJSON)
    )

    let line = try #require(decoded.curves.first)
    #expect(decoded.displayUnit == .millimeter)
    #expect(decoded.displayUnitSymbol == "mm")
    #expect(line.displayUnitSymbol == "mm")
    #expect(line.pointDisplayScale == 1_000.0)
    #expect(line.curvatureDisplayUnitSymbol == "1/mm")
    #expect(line.curvatureDisplayScale == 0.001)
    #expect(abs(line.approximateLengthDisplayValue - 10.0) < 1.0e-12)
}

private func curveAnalysisPoint(x: Double, y: Double) -> SketchPoint {
    SketchPoint(
        x: .length(x, .meter),
        y: .length(y, .meter)
    )
}

private func twoLineCurveAnalysisDocument(
    secondStart: SketchPoint,
    secondEnd: SketchPoint,
    constraint: (SketchEntityID, SketchEntityID) -> SketchConstraint
) throws -> (
    document: DesignDocument,
    featureID: FeatureID,
    firstLineID: SketchEntityID,
    secondLineID: SketchEntityID
) {
    var document = DesignDocument.empty()
    let featureID = try document.createLineSketch(
        name: "Two Line Curve Analysis",
        plane: .xy,
        start: curveAnalysisPoint(x: 0.0, y: 0.0),
        end: curveAnalysisPoint(x: 0.003, y: 0.0)
    )
    guard var feature = document.cadDocument.designGraph.nodes[featureID],
          case var .sketch(sketch) = feature.operation,
          let firstLineID = sketch.entities.keys.first else {
        throw EditorError(
            code: .referenceUnresolved,
            message: "Two line curve analysis setup requires a line sketch."
        )
    }
    let secondLineID = SketchEntityID()
    sketch.entities[secondLineID] = .line(
        SketchLine(
            start: secondStart,
            end: secondEnd
        )
    )
    sketch.constraints = [constraint(firstLineID, secondLineID)]
    feature.operation = .sketch(sketch)
    document.cadDocument.designGraph.nodes[featureID] = feature
    document.cadDocument.designGraph.revision = document.cadDocument.designGraph.revision.advanced()
    return (document, featureID, firstLineID, secondLineID)
}

private func twoSplineCurveAnalysisDocument() throws -> (
    document: DesignDocument,
    firstSplineID: SketchEntityID,
    secondSplineID: SketchEntityID
) {
    var document = DesignDocument.empty()
    let featureID = try document.createSplineSketch(
        name: "Two Spline Curve Analysis",
        plane: .xy,
        spline: SketchSpline(controlPoints: [
            curveAnalysisPoint(x: 0.000, y: 0.0),
            curveAnalysisPoint(x: 0.001, y: 0.0),
            curveAnalysisPoint(x: 0.002, y: 0.0),
            curveAnalysisPoint(x: 0.003, y: 0.0),
        ])
    )
    guard var feature = document.cadDocument.designGraph.nodes[featureID],
          case var .sketch(sketch) = feature.operation,
          let firstSplineID = sketch.entities.keys.first else {
        throw EditorError(
            code: .referenceUnresolved,
            message: "Two spline curve analysis setup requires a spline sketch."
        )
    }
    let secondSplineID = SketchEntityID()
    sketch.entities[secondSplineID] = .spline(
        SketchSpline(controlPoints: [
            curveAnalysisPoint(x: 0.003, y: 0.0),
            curveAnalysisPoint(x: 0.004, y: 0.0),
            curveAnalysisPoint(x: 0.005, y: 0.0),
            curveAnalysisPoint(x: 0.006, y: 0.0),
        ])
    )
    sketch.constraints = [
        .coincident(
            .splineControlPoint(entity: firstSplineID, index: 3),
            .splineControlPoint(entity: secondSplineID, index: 0)
        ),
        .smoothSplineEndpoints(SketchSplineEndpointTangencyConstraint(
            first: SketchSplineEndpointReference(splineID: firstSplineID, endpoint: .end),
            second: SketchSplineEndpointReference(splineID: secondSplineID, endpoint: .start),
            orientation: .aligned
        )),
    ]
    feature.operation = .sketch(sketch)
    document.cadDocument.designGraph.nodes[featureID] = feature
    document.cadDocument.designGraph.revision = document.cadDocument.designGraph.revision.advanced()
    return (document, firstSplineID, secondSplineID)
}
