import Foundation
import SwiftCAD
import Testing
@testable import RupaCore

/// A Bridge Curve is derived from its source everywhere it is used: references to its ends
/// follow a regenerated degree, bridges on bridges regenerate in dependency order, its source
/// stays editable, and every command that reads it (Reverse, projection, Offset, curve analysis)
/// reads its own degree and knots.
@MainActor
@Suite struct BridgeCurveDerivationTests {
    private func mm(_ value: Double) -> CADExpression { .length(value, .millimeter) }
    private func point(_ x: Double, _ y: Double) -> SketchPoint { SketchPoint(x: mm(x), y: mm(y)) }

    /// One sketch holding `entities`, with its feature.
    private func makeDocument(_ entities: [SketchEntityID: SketchEntity]) throws -> (DesignDocument, FeatureID) {
        var document = DesignDocument.empty()
        let featureID = try document.createLineSketch(name: "Sources", plane: .xy, start: point(-20, -20), end: point(-19, -20))
        guard var feature = document.cadDocument.designGraph.nodes[featureID],
              case var .sketch(sketch) = feature.operation else {
            throw EditorError(code: .referenceUnresolved, message: "The sketch is missing.")
        }
        sketch.entities.merge(entities) { _, new in new }
        feature.operation = .sketch(sketch)
        document.cadDocument.designGraph.nodes[featureID] = feature
        document.cadDocument.designGraph.revision = document.cadDocument.designGraph.revision.advanced()
        return (document, featureID)
    }

    private func sketch(_ document: DesignDocument, _ featureID: FeatureID) throws -> Sketch {
        guard case .sketch(let sketch) = document.cadDocument.designGraph.nodes[featureID]?.operation else {
            throw EditorError(code: .referenceUnresolved, message: "The sketch is missing.")
        }
        return sketch
    }

    private func spline(_ document: DesignDocument, _ featureID: FeatureID, _ entityID: SketchEntityID) throws -> SketchSpline {
        guard case .spline(let spline) = try sketch(document, featureID).entities[entityID] else {
            throw EditorError(code: .referenceUnresolved, message: "The spline is missing.")
        }
        return spline
    }

    /// Control points in millimeters.
    private func points(_ document: DesignDocument, _ spline: SketchSpline) throws -> [Point2D] {
        try spline.controlPoints.map {
            Point2D(
                x: try document.cadDocument.parameters.resolvedValue(for: $0.x).value * 1000,
                y: try document.cadDocument.parameters.resolvedValue(for: $0.y).value * 1000
            )
        }
    }

    private func curve(_ document: DesignDocument, _ spline: SketchSpline) throws -> BSplineCurve2D {
        let knots = try #require(spline.knotVector)
        return BSplineCurve2D(degree: spline.degree, knots: knots, controlPoints: try points(document, spline))
    }

    private func dense(_ curve: BSplineCurve2D, count: Int = 2000) throws -> [Point2D] {
        let lower = curve.knots[0], upper = curve.knots[curve.knots.count - 1]
        return try (0...count).map { try curve.point(at: lower + (upper - lower) * Double($0) / Double(count), tolerance: .standard) }
    }

    private func target(_ document: DesignDocument, _ featureID: FeatureID, _ entityID: SketchEntityID) throws -> SelectionTarget {
        let sceneNodeID = try #require(document.productMetadata.sceneNodes.first { _, node in
            node.reference?.kind == .sketch && node.reference?.featureID == featureID
        }?.key)
        return SelectionTarget(
            sceneNodeID: sceneNodeID,
            component: .sketchEntity(SelectionComponentID.sketchEntity(featureID: featureID, entityID: entityID))
        )
    }

    private func signedCurvature(_ p: [Point2D], atEnd: Bool) -> Double {
        let n = Double(p.count - 1)
        let (a, b, c) = atEnd ? (p[p.count - 1], p[p.count - 2], p[p.count - 3]) : (p[0], p[1], p[2])
        let d1 = Point2D(x: n * (b.x - a.x), y: n * (b.y - a.y))
        let d2 = Point2D(x: n * (n - 1) * (c.x - 2 * b.x + a.x), y: n * (n - 1) * (c.y - 2 * b.y + a.y))
        // At the end the points run backwards, which reverses the sign of the curvature.
        let reversedCurvature = (d1.x * d2.y - d1.y * d2.x) / pow(hypot(d1.x, d1.y), 3)
        return atEnd ? -reversedCurvature : reversedCurvature
    }

    /// Lines (0,0)-(3,0), (6,3)-(6,6) and (10,0)-(13,0) mm.
    private func threeLines() throws -> (DesignDocument, FeatureID, SketchEntityID, SketchEntityID, SketchEntityID) {
        let l1 = SketchEntityID(), l2 = SketchEntityID(), l3 = SketchEntityID()
        let (document, featureID) = try makeDocument([
            l1: .line(SketchLine(start: point(0, 0), end: point(3, 0))),
            l2: .line(SketchLine(start: point(6, 3), end: point(6, 6))),
            l3: .line(SketchLine(start: point(10, 0), end: point(13, 0))),
        ])
        return (document, featureID, l1, l2, l3)
    }

    @Test func aRelationOnABridgeEndFollowsTheEndWhenTheDegreeChanges() throws {
        var (document, featureID, l1, l2, l3) = try threeLines()
        let bridgeID = try document.createBridgeCurve(
            featureID: featureID,
            firstEndpoint: BridgeCurveEndpoint(reference: .lineEnd(l1)),
            secondEndpoint: BridgeCurveEndpoint(reference: .lineStart(l2)),
            continuity: .g1
        )
        try document.addSketchConstraint(featureID: featureID, constraint: .coincident(.splineControlPoint(entity: bridgeID, index: 3), .lineEnd(l3)))
        let source = try #require(document.productMetadata.bridgeCurveSources.values.first)
        try document.setBridgeCurveParameters(sourceID: source.id, continuity: BridgeCurveContinuity(first: .g2, second: .g2))

        let bridge = try spline(document, featureID, bridgeID)
        #expect(bridge.degree == 5 && bridge.controlPoints.count == 6)
        let constraints = try sketch(document, featureID).constraints
        #expect(constraints.contains(.coincident(.splineControlPoint(entity: bridgeID, index: 5), .lineEnd(l3))))
        #expect(constraints.contains { "\($0)".contains("index: 3") } == false)
        // The relation still holds: the bridge's end is the third line's end.
        guard case .line(let third) = try sketch(document, featureID).entities[l3] else { return }
        let end = try points(document, bridge).last!
        #expect(abs(end.x - (try document.cadDocument.parameters.resolvedValue(for: third.end.x).value * 1000)) <= 1e-9)
        #expect(abs(end.y - (try document.cadDocument.parameters.resolvedValue(for: third.end.y).value * 1000)) <= 1e-9)
    }

    @Test func aBridgeRefusesRelationsOnItsInteriorAndOnItsContinuity() throws {
        var (document, featureID, l1, l2, l3) = try threeLines()
        let bridgeID = try document.createBridgeCurve(
            featureID: featureID,
            firstEndpoint: BridgeCurveEndpoint(reference: .lineEnd(l1)),
            secondEndpoint: BridgeCurveEndpoint(reference: .lineStart(l2)),
            continuity: .g1
        )
        let before = document.cadDocument.designGraph
        #expect(throws: EditorError.self) {
            try document.addSketchConstraint(featureID: featureID, constraint: .coincident(.splineControlPoint(entity: bridgeID, index: 1), .lineEnd(l3)))
        }
        #expect(throws: EditorError.self) {
            try document.addSketchConstraint(featureID: featureID, constraint: .splineEndpointTangent(SketchSplineLineTangencyConstraint(
                splineEndpoint: SketchSplineEndpointReference(splineID: bridgeID, endpoint: .start),
                line: l3,
                orientation: .aligned
            )))
        }
        #expect(document.cadDocument.designGraph == before)
    }

    /// A bridge whose end lies on another bridge meets it at G2 however their IDs sort, and moving
    /// a source of the first leaves the unrelated source alone.
    @Test func aBridgeOnABridgeRegeneratesAfterIt() throws {
        for _ in 0..<8 {
            var (document, featureID, l1, l2, l3) = try threeLines()
            let a = try document.createBridgeCurve(
                featureID: featureID,
                firstEndpoint: BridgeCurveEndpoint(reference: .lineEnd(l1)),
                secondEndpoint: BridgeCurveEndpoint(reference: .lineStart(l2)),
                continuity: .g1
            )
            let b = try document.createBridgeCurve(
                featureID: featureID,
                firstEndpoint: BridgeCurveEndpoint(reference: .splineControlPoint(entity: a, index: 3)),
                secondEndpoint: BridgeCurveEndpoint(reference: .lineStart(l3)),
                continuity: BridgeCurveContinuity(first: .g2, second: .g1)
            )
            let firstLine = try sketch(document, featureID).entities[l1]
            try document.moveSketchEntityPoint(target: target(document, featureID, l2), handle: .lineStart, deltaX: mm(1), deltaY: mm(0.5))
            let ap = try points(document, spline(document, featureID, a)), bp = try points(document, spline(document, featureID, b))
            #expect(hypot(ap.last!.x - bp[0].x, ap.last!.y - bp[0].y) <= 1e-9)
            #expect(abs(signedCurvature(ap, atEnd: true) - signedCurvature(bp, atEnd: false)) <= 1e-9)
            #expect(try sketch(document, featureID).entities[l1] == firstLine)
        }
    }

    @Test func bridgesOnEachOtherInACycleAreRefused() throws {
        var (document, featureID, l1, l2, _) = try threeLines()
        let a = try document.createBridgeCurve(
            featureID: featureID,
            firstEndpoint: BridgeCurveEndpoint(reference: .lineEnd(l1)),
            secondEndpoint: BridgeCurveEndpoint(reference: .lineStart(l2)),
            continuity: .g1
        )
        let b = try document.createBridgeCurve(
            featureID: featureID,
            firstEndpoint: BridgeCurveEndpoint(reference: .splineControlPoint(entity: a, index: 3)),
            secondEndpoint: BridgeCurveEndpoint(reference: .lineEnd(l2)),
            continuity: .g1
        )
        let sourceA = try #require(document.productMetadata.bridgeCurveSources.values.first { $0.entityID == a })
        let before = document.cadDocument.designGraph
        #expect(throws: EditorError.self) {
            try document.setBridgeCurveParameters(
                sourceID: sourceA.id,
                secondEndpoint: BridgeCurveEndpoint(reference: .splineControlPoint(entity: b, index: 3))
            )
        }
        #expect(document.cadDocument.designGraph == before)
    }

    /// Two open cubic splines (0,0)…(3,1) and (6,3)…(9,4) mm.
    private func twoSplines() throws -> (DesignDocument, FeatureID, SketchEntityID, SketchEntityID) {
        let s1 = SketchEntityID(), s2 = SketchEntityID()
        let (document, featureID) = try makeDocument([
            s1: .spline(SketchSpline(controlPoints: [point(0, 0), point(1, 1), point(2, 0), point(3, 1)])),
            s2: .spline(SketchSpline(controlPoints: [point(6, 3), point(7, 4), point(8, 3), point(9, 4)])),
        ])
        return (document, featureID, s1, s2)
    }

    @Test(arguments: [BridgeCurveEndpointContinuity.g2, .g3])
    func aSourceSplineEndStaysEditableUnderASmoothBridge(level: BridgeCurveEndpointContinuity) throws {
        var (document, featureID, s1, s2) = try twoSplines()
        let bridgeID = try document.createBridgeCurve(
            featureID: featureID,
            firstEndpoint: BridgeCurveEndpoint(reference: .splineControlPoint(entity: s1, index: 3)),
            secondEndpoint: BridgeCurveEndpoint(reference: .splineControlPoint(entity: s2, index: 0)),
            continuity: BridgeCurveContinuity(first: level, second: level)
        )
        let firstSource = try spline(document, featureID, s1)
        try document.moveSketchSplineControlPoint(target: target(document, featureID, s2), controlPointIndex: 0, deltaX: mm(0.5), deltaY: mm(0.5))
        #expect(try spline(document, featureID, s1) == firstSource)
        let bridge = try points(document, spline(document, featureID, bridgeID))
        #expect(hypot(bridge.last!.x - 6.5, bridge.last!.y - 3.5) <= 1e-9)
    }

    /// Reversing a quintic G2/G0 bridge keeps the curve: G2 stays at the first line.
    @Test func aReversedBridgeKeepsItsShapeAndItsContinuityAtEachEnd() throws {
        var (document, featureID, l1, l2, _) = try threeLines()
        let bridgeID = try document.createBridgeCurve(
            featureID: featureID,
            firstEndpoint: BridgeCurveEndpoint(reference: .lineEnd(l1)),
            secondEndpoint: BridgeCurveEndpoint(reference: .lineStart(l2)),
            continuity: BridgeCurveContinuity(first: .g2, second: .g1)
        )
        let before = try dense(curve(document, spline(document, featureID, bridgeID)))
        try document.reverseSketchCurve(target: target(document, featureID, bridgeID))
        let source = try #require(document.productMetadata.bridgeCurveSources.values.first)
        #expect(source.continuity == BridgeCurveContinuity(first: .g1, second: .g2))
        #expect(source.firstEndpoint.reference == .lineStart(l2))
        let reversed = try spline(document, featureID, bridgeID)
        #expect(reversed.degree == 4)
        let after = try dense(curve(document, reversed))
        for (p, q) in zip(before, after.reversed()) {
            #expect(hypot(p.x - q.x, p.y - q.y) <= 1e-9)
        }
    }

    @Test func aReverseKeepsTheTrimRecordOfEveryBridge() throws {
        var (document, featureID, l1, l2, _) = try threeLines()
        _ = try document.createBridgeCurve(
            featureID: featureID,
            firstEndpoint: BridgeCurveEndpoint(reference: .entity(l1), parameter: .scalar(0.5), trimSide: .towardStart),
            secondEndpoint: BridgeCurveEndpoint(reference: .lineStart(l2)),
            continuity: .g1,
            trimsSourceCurves: true
        )
        #expect(document.productMetadata.bridgeCurveSources.values.first?.trimRecord != nil)
        try document.reverseSketchCurve(target: target(document, featureID, l2))
        let source = try #require(document.productMetadata.bridgeCurveSources.values.first)
        #expect(source.trimRecord != nil)
        // The untrimmed end on the reversed line follows it: the line's start became its end.
        #expect(source.trimRecord?.untrimmedSecondEndpoint.reference == .lineEnd(l2))
    }

    /// A sextic bridge (G3/G2, seven control points) is not a cubic chain even though its point
    /// count would make one: projection and Offset read its own curve.
    @Test func projectionAndOffsetReadASexticBridgeOnItsOwnCurve() throws {
        let s1 = SketchEntityID(), s2 = SketchEntityID()
        var (document, featureID) = try makeDocument([
            s1: .spline(SketchSpline(controlPoints: [point(0, 0), point(1, 0), point(2, 0), point(3, 0)])),
            s2: .spline(SketchSpline(controlPoints: [point(6, 3), point(7, 3), point(8, 3), point(9, 3)])),
        ])
        let bridgeID = try document.createBridgeCurve(
            featureID: featureID,
            firstEndpoint: BridgeCurveEndpoint(reference: .splineControlPoint(entity: s1, index: 3)),
            secondEndpoint: BridgeCurveEndpoint(reference: .splineControlPoint(entity: s2, index: 0)),
            continuity: BridgeCurveContinuity(first: .g3, second: .g2)
        )
        let bridge = try spline(document, featureID, bridgeID)
        #expect(bridge.degree == 6 && bridge.controlPoints.count == 7)
        let original = try dense(curve(document, bridge))

        let projectedID = try document.projectSketchCurvesToConstructionPlane(targets: [target(document, featureID, bridgeID)], plane: .xy)
        guard case .spline(let projected)? = try sketch(document, projectedID).entities.values.first else {
            Issue.record("The projection must be a spline.")
            return
        }
        #expect(projected.degree == 6)
        for (p, q) in zip(original, try dense(curve(document, projected))) {
            #expect(hypot(p.x - q.x, p.y - q.y) <= 1e-9)
        }

        let offsetID = try #require(try document.offsetCurve(target: target(document, featureID, bridgeID), distance: mm(0.5), options: OffsetCurveOptions()).first)
        guard case .spline(let offset)? = try sketch(document, offsetID).entities.values.first else {
            Issue.record("The offset must be a spline.")
            return
        }
        let offsetPoints = try dense(curve(document, offset), count: 300)
        let sourcePoints = try dense(curve(document, bridge), count: 8000)
        for q in offsetPoints {
            let nearest = sourcePoints.map { hypot($0.x - q.x, $0.y - q.y) }.min()!
            #expect(abs(nearest - 0.5) <= 1e-3)
        }
    }

    @Test func aClosedSplineProjectsClosed() throws {
        let loop = SketchEntityID()
        let k = 5.5
        var (document, featureID) = try makeDocument([
            loop: .spline(SketchSpline(
                controlPoints: [(10, 0), (10, k), (k, 10), (0, 10), (-k, 10), (-10, k), (-10, 0), (-10, -k), (-k, -10), (0, -10), (k, -10), (10, -k), (10, 0)]
                    .map { point($0.0, $0.1) },
                isClosed: true
            )),
        ])
        let projectedID = try document.projectSketchCurvesToConstructionPlane(targets: [target(document, featureID, loop)], plane: .xy)
        guard case .spline(let projected)? = try sketch(document, projectedID).entities.values.first else {
            Issue.record("The projection must be a spline.")
            return
        }
        #expect(projected.isClosed)
    }

    /// Curve analysis reports each bridge end's declared continuity and measures it on the exact
    /// curves, G3 included.
    @Test func analysisReadsTheBridgeContinuityAtEachEnd() throws {
        var (document, featureID, s1, s2) = try twoSplines()
        let bridgeID = try document.createBridgeCurve(
            featureID: featureID,
            firstEndpoint: BridgeCurveEndpoint(reference: .splineControlPoint(entity: s1, index: 3)),
            secondEndpoint: BridgeCurveEndpoint(reference: .splineControlPoint(entity: s2, index: 0)),
            continuity: BridgeCurveContinuity(first: .g3, second: .g1)
        )
        let analysis = try CurveAnalysisService().analyze(document: document, featureID: featureID, entityID: bridgeID, displayUnit: .millimeter)
        let joins = analysis.continuityJoins.filter { $0.constraintKinds.contains("bridgeCurve") }
        #expect(joins.count == 2)
        let bridgeStart = "splineControlPoint:\(bridgeID.description):0"
        let start = try #require(joins.first { $0.firstReference == bridgeStart || $0.secondReference == bridgeStart })
        #expect(start.requiredContinuity == .g3 && start.continuity == .g3)
        let end = try #require(joins.first { $0 != start })
        #expect(end.requiredContinuity == .g1)
        #expect(end.continuity == .g1 || end.continuity == .g2 || end.continuity == .g3)
    }
}
