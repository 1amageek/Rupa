import Foundation
import SwiftCAD
import Testing
@testable import RupaCore

/// Dependent Curve Extend reaches another curve exactly; Align on two curves aligns their nearest
/// ends.
@MainActor
@Suite struct DependentExtendAndAlignTests {
    private func mm(_ value: Double) -> CADExpression { .length(value, .millimeter) }
    private func point(_ x: Double, _ y: Double) -> SketchPoint { SketchPoint(x: mm(x), y: mm(y)) }

    private func document(_ entities: [SketchEntityID: SketchEntity]) throws -> (DesignDocument, FeatureID) {
        var document = DesignDocument.empty()
        let featureID = try document.createLineSketch(name: "Extend", plane: .xy, start: point(-40, -40), end: point(-39, -40))
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

    private func end(_ document: DesignDocument, _ featureID: FeatureID, _ reference: SketchReference) throws -> Point2D {
        guard case .sketch(let sketch) = document.cadDocument.designGraph.nodes[featureID]?.operation,
              let sample = try SketchCurveEndpointResolver().sample(for: reference, sketch: sketch, document: document) else {
            throw EditorError(code: .referenceUnresolved, message: "The end is missing.")
        }
        return Point2D(x: sample.sample.point.x * 1000, y: sample.sample.point.y * 1000)
    }

    @Test func aLineExtendsToMeetAnotherLine() throws {
        let lineID = SketchEntityID(), wallID = SketchEntityID()
        var (document, featureID) = try document([
            lineID: .line(SketchLine(start: point(0, 0), end: point(5, 0))),
            wallID: .line(SketchLine(start: point(10, -5), end: point(12, 5))),
        ])
        try document.extendSketchCurve(
            target: target(document, featureID, .sketchPointHandle(featureID: featureID, entityID: lineID, handle: .lineEnd)),
            until: target(document, featureID, .sketchEntity(featureID: featureID, entityID: wallID)),
            shape: .linear
        )
        let reached = try end(document, featureID, .lineEnd(lineID))
        #expect(abs(reached.x - 11) <= 1e-9 && abs(reached.y) <= 1e-9)
    }

    @Test func aSplineExtendsNaturallyToMeetALineAtEitherEnd() throws {
        let splineID = SketchEntityID(), wallID = SketchEntityID(), floorID = SketchEntityID()
        var (document, featureID) = try document([
            splineID: .spline(SketchSpline(controlPoints: [(0, 0), (3, 2), (6, 2), (9, 0)].map { point($0.0, $0.1) })),
            wallID: .line(SketchLine(start: point(11, -10), end: point(11, 10))),
            floorID: .line(SketchLine(start: point(-10, -1), end: point(10, -1))),
        ])
        try document.extendSketchCurve(
            target: target(document, featureID, .sketchControlPoint(featureID: featureID, entityID: splineID, index: 3)),
            until: target(document, featureID, .sketchEntity(featureID: featureID, entityID: wallID)),
            shape: .natural
        )
        guard case .spline(let extended) = document.cadDocument.designGraph.nodes[featureID].flatMap({ node -> SketchSpline? in
            guard case .sketch(let sketch) = node.operation, case .spline(let spline) = sketch.entities[splineID] else { return nil }
            return spline
        }).map({ SketchEntity.spline($0) }) else {
            Issue.record("The spline must remain.")
            return
        }
        let reached = try end(document, featureID, .splineControlPoint(entity: splineID, index: extended.controlPoints.count - 1))
        #expect(abs(reached.x - 11) <= 1e-7)
        try document.extendSketchCurve(
            target: target(document, featureID, .sketchControlPoint(featureID: featureID, entityID: splineID, index: 0)),
            until: target(document, featureID, .sketchEntity(featureID: featureID, entityID: floorID)),
            shape: .natural
        )
        let start = try end(document, featureID, .splineControlPoint(entity: splineID, index: 0))
        #expect(abs(start.y + 1) <= 1e-7)
    }

    @Test func anExtensionThatNeverMeetsTheLimitIsRefused() throws {
        let lineID = SketchEntityID(), parallelID = SketchEntityID()
        var (document, featureID) = try document([
            lineID: .line(SketchLine(start: point(0, 0), end: point(5, 0))),
            parallelID: .line(SketchLine(start: point(0, 3), end: point(20, 3))),
        ])
        let before = document.cadDocument.designGraph
        #expect(throws: EditorError.self) {
            try document.extendSketchCurve(
                target: target(document, featureID, .sketchPointHandle(featureID: featureID, entityID: lineID, handle: .lineEnd)),
                until: target(document, featureID, .sketchEntity(featureID: featureID, entityID: parallelID)),
                shape: .linear
            )
        }
        #expect(document.cadDocument.designGraph == before)
    }

    @Test func alignOnTwoCurvesAlignsTheSecondsNearestEndWithTheFirsts() throws {
        let firstID = SketchEntityID(), secondID = SketchEntityID()
        var (document, featureID) = try document([
            firstID: .line(SketchLine(start: point(0, 0), end: point(5, 0))),
            secondID: .line(SketchLine(start: point(6, 1), end: point(10, 4))),
        ])
        try document.alignSketchCurveEnds(
            first: target(document, featureID, .sketchEntity(featureID: featureID, entityID: firstID)),
            second: target(document, featureID, .sketchEntity(featureID: featureID, entityID: secondID))
        )
        let moved = try end(document, featureID, .lineStart(secondID))
        #expect(abs(moved.x - 5) <= 1e-9 && abs(moved.y) <= 1e-9)
        let fixed = try end(document, featureID, .lineEnd(firstID))
        #expect(abs(fixed.x - 5) <= 1e-9 && abs(fixed.y) <= 1e-9)
    }
}
