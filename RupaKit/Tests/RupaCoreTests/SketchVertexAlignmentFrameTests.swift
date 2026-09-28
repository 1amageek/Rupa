import Foundation
import SwiftCAD
import Testing
@testable import RupaCore

/// Align Vertex aligns an end to a point at a Parameter of a reference curve, and gives an end the
/// tangent (G1) and curvature (G2) of an arc or spline where no sketch constraint expresses it.
@MainActor
@Suite struct SketchVertexAlignmentFrameTests {
    private func mm(_ value: Double) -> CADExpression { .length(value, .millimeter) }
    private func point(_ x: Double, _ y: Double) -> SketchPoint { SketchPoint(x: mm(x), y: mm(y)) }

    private func document(_ entities: [SketchEntityID: SketchEntity]) throws -> (DesignDocument, FeatureID) {
        var document = DesignDocument.empty()
        let featureID = try document.createLineSketch(name: "Align", plane: .xy, start: point(-40, -40), end: point(-39, -40))
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

    private func target(_ document: DesignDocument, _ featureID: FeatureID, _ component: SelectionComponentID) throws -> SelectionTarget {
        let sceneNodeID = try #require(document.productMetadata.sceneNodes.first { _, node in
            node.reference?.kind == .sketch && node.reference?.featureID == featureID
        }?.key)
        return SelectionTarget(sceneNodeID: sceneNodeID, component: .sketchEntity(component))
    }

    private func sketch(_ document: DesignDocument, _ featureID: FeatureID) throws -> Sketch {
        guard case .sketch(let sketch) = document.cadDocument.designGraph.nodes[featureID]?.operation else {
            throw EditorError(code: .referenceUnresolved, message: "The sketch is missing.")
        }
        return sketch
    }

    /// The resolver's sample of `reference` (an end) or of `entity` at `fraction`.
    private func sample(_ document: DesignDocument, _ featureID: FeatureID, end reference: SketchReference) throws -> SketchCurveEndpointSample {
        try #require(try SketchCurveEndpointResolver().sample(for: reference, sketch: sketch(document, featureID), document: document))
    }

    private func sample(_ document: DesignDocument, _ featureID: FeatureID, entity: SketchEntityID, fraction: Double) throws -> SketchCurveEndpointSample {
        try #require(try SketchCurveEndpointResolver().sample(
            for: BridgeCurveEndpoint(reference: .entity(entity), parameter: .scalar(fraction)),
            sketch: sketch(document, featureID),
            document: document
        ))
    }

    private func curvatureVector(_ s: SketchCurveEndpointSample) -> Point2D {
        Point2D(x: s.sample.curvature * s.sample.normal.x, y: s.sample.curvature * s.sample.normal.y)
    }

    private let referenceSpline = SketchSpline(controlPoints: [(0, 0), (4, 6), (10, 6), (14, 0)].map { (x: Double, y: Double) in
        SketchPoint(x: .length(x, .millimeter), y: .length(y, .millimeter))
    })

    @Test(arguments: [SketchVertexAlignmentContinuity.g0, .g1, .g2])
    func aSplineEndAlignsToAParameterOfACurve(continuity: SketchVertexAlignmentContinuity) throws {
        let referenceID = SketchEntityID(), targetID = SketchEntityID()
        var (document, featureID) = try document([
            referenceID: .spline(referenceSpline),
            targetID: .spline(SketchSpline(controlPoints: [(20, 10), (24, 14), (28, 12), (32, 16)].map { point($0.0, $0.1) })),
        ])
        try document.alignSketchVertex(
            target: target(document, featureID, .sketchControlPoint(featureID: featureID, entityID: targetID, index: 0)),
            reference: target(document, featureID, .sketchEntity(featureID: featureID, entityID: referenceID)),
            options: SketchVertexAlignmentOptions(continuity: continuity, referenceParameter: .scalar(0.3))
        )
        let onReference = try sample(document, featureID, entity: referenceID, fraction: 0.3)
        let targetStart = try sample(document, featureID, end: .splineControlPoint(entity: targetID, index: 0))
        #expect(hypot(targetStart.sample.point.x - onReference.sample.point.x, targetStart.sample.point.y - onReference.sample.point.y) <= 1e-12)
        if continuity != .g0 {
            let cross = targetStart.sample.tangent.x * onReference.sample.tangent.y - targetStart.sample.tangent.y * onReference.sample.tangent.x
            #expect(abs(cross) <= 1e-9)
        }
        if continuity == .g2 {
            let a = curvatureVector(targetStart), b = curvatureVector(onReference)
            #expect(hypot(a.x - b.x, a.y - b.y) <= 1e-6 * max(1, hypot(b.x, b.y)))
        }
        // Nothing holds it: the alignment is made once.
        #expect(try sketch(document, featureID).constraints.isEmpty)
    }

    /// Two arcs meeting end to start: G1 turns the target arc to leave along the reference's end
    /// tangent; G2 also takes its radius.
    @Test(arguments: [SketchVertexAlignmentContinuity.g1, .g2])
    func anArcEndTakesAnotherArcsTangentAndCurvature(continuity: SketchVertexAlignmentContinuity) throws {
        let referenceID = SketchEntityID(), targetID = SketchEntityID()
        var (document, featureID) = try document([
            referenceID: .arc(SketchArc(center: point(0, 0), radius: mm(10), startAngle: .angle(0, .radian), endAngle: .angle(Double.pi / 2, .radian))),
            targetID: .arc(SketchArc(center: point(30, 0), radius: mm(6), startAngle: .angle(0, .radian), endAngle: .angle(1, .radian))),
        ])
        try document.alignSketchVertex(
            target: target(document, featureID, .sketchPointHandle(featureID: featureID, entityID: targetID, handle: .arcStart)),
            reference: target(document, featureID, .sketchPointHandle(featureID: featureID, entityID: referenceID, handle: .arcEnd)),
            options: SketchVertexAlignmentOptions(continuity: continuity)
        )
        let end = try sample(document, featureID, end: .arcEnd(referenceID))
        let start = try sample(document, featureID, end: .arcStart(targetID))
        #expect(hypot(start.sample.point.x - end.sample.point.x, start.sample.point.y - end.sample.point.y) <= 1e-9)
        // Smooth: the target leaves the point the way the reference goes on past its end.
        #expect(hypot(start.outgoingTangent.x + end.outgoingTangent.x, start.outgoingTangent.y + end.outgoingTangent.y) <= 1e-9)
        if continuity == .g2 {
            #expect(abs(start.sample.curvature - end.sample.curvature) <= 1e-6)
        }
        #expect(try sketch(document, featureID).constraints.contains(.coincident(.arcEnd(referenceID), .arcStart(targetID))))
    }

    @Test func aSplineEndTakesAnArcsCurvature() throws {
        let arcID = SketchEntityID(), splineID = SketchEntityID()
        var (document, featureID) = try document([
            arcID: .arc(SketchArc(center: point(0, 0), radius: mm(10), startAngle: .angle(0, .radian), endAngle: .angle(Double.pi / 2, .radian))),
            splineID: .spline(SketchSpline(controlPoints: [(-4, 14), (-8, 16), (-12, 12), (-16, 16)].map { point($0.0, $0.1) })),
        ])
        try document.alignSketchVertex(
            target: target(document, featureID, .sketchControlPoint(featureID: featureID, entityID: splineID, index: 0)),
            reference: target(document, featureID, .sketchPointHandle(featureID: featureID, entityID: arcID, handle: .arcEnd)),
            options: SketchVertexAlignmentOptions(continuity: .g2)
        )
        let end = try sample(document, featureID, end: .arcEnd(arcID))
        let start = try sample(document, featureID, end: .splineControlPoint(entity: splineID, index: 0))
        let a = curvatureVector(start), b = curvatureVector(end)
        #expect(hypot(a.x - b.x, a.y - b.y) <= 1e-6 * hypot(b.x, b.y))
        #expect(hypot(start.outgoingTangent.x + end.outgoingTangent.x, start.outgoingTangent.y + end.outgoingTangent.y) <= 1e-9)
    }

    /// An arc turns counterclockwise, so G2 to a reference bending the other way is refused.
    @Test func anArcCannotTakeACurvatureBendingTheOtherWay() throws {
        let referenceID = SketchEntityID(), targetID = SketchEntityID()
        var (document, featureID) = try document([
            referenceID: .arc(SketchArc(center: point(0, 0), radius: mm(10), startAngle: .angle(0, .radian), endAngle: .angle(Double.pi / 2, .radian))),
            targetID: .arc(SketchArc(center: point(30, 0), radius: mm(6), startAngle: .angle(0, .radian), endAngle: .angle(1, .radian))),
        ])
        let before = document.cadDocument.designGraph
        #expect(throws: EditorError.self) {
            try document.alignSketchVertex(
                target: target(document, featureID, .sketchPointHandle(featureID: featureID, entityID: targetID, handle: .arcEnd)),
                reference: target(document, featureID, .sketchPointHandle(featureID: featureID, entityID: referenceID, handle: .arcEnd)),
                options: SketchVertexAlignmentOptions(continuity: .g2)
            )
        }
        #expect(document.cadDocument.designGraph == before)
    }
}
