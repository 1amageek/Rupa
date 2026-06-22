import Foundation
import SwiftCAD
import Testing
@testable import RupaCore

@Test func canvasArcClickDraftUsesDefaultQuarterArc() throws {
    let center = Point2D(x: -0.04, y: 0.025)

    let draft = try CanvasSketchCurveDrafts.arc(centeredAt: center)

    #expect(draft.center == center)
    #expect(abs(draft.radiusMeters - 0.012) < 1.0e-12)
    #expect(abs(draft.startAngleRadians - 0.0) < 1.0e-12)
    #expect(abs(draft.endAngleRadians - Double.pi / 2.0) < 1.0e-12)
}

@Test func canvasArcDragDraftUsesCenterAndRadiusPoint() throws {
    let center = Point2D(x: 0.01, y: -0.02)
    let radiusPoint = Point2D(x: 0.04, y: 0.02)

    let draft = try CanvasSketchCurveDrafts.arc(
        fromCenter: center,
        toRadiusPoint: radiusPoint
    )
    let expectedEndAngle = atan2(0.04, 0.03)

    #expect(draft.center == center)
    #expect(abs(draft.radiusMeters - 0.05) < 1.0e-12)
    #expect(abs(draft.startAngleRadians - (expectedEndAngle - Double.pi / 2.0)) < 1.0e-12)
    #expect(abs(draft.endAngleRadians - expectedEndAngle) < 1.0e-12)
}

@Test func canvasArcDraftAppliesRadiusAndSpanOverrides() throws {
    let center = Point2D(x: 0.01, y: -0.02)
    let radiusPoint = Point2D(x: 0.04, y: 0.02)
    let span = Double.pi / 3.0

    let clickDraft = try CanvasSketchCurveDrafts.arc(
        centeredAt: center,
        radiusMeters: 0.018,
        spanAngleRadians: span
    )
    let dragDraft = try CanvasSketchCurveDrafts.arc(
        fromCenter: center,
        toRadiusPoint: radiusPoint,
        radiusMeters: 0.019,
        spanAngleRadians: span
    )
    let expectedEndAngle = atan2(0.04, 0.03)

    #expect(abs(clickDraft.radiusMeters - 0.018) < 1.0e-12)
    #expect(abs(clickDraft.startAngleRadians - 0.0) < 1.0e-12)
    #expect(abs(clickDraft.endAngleRadians - span) < 1.0e-12)
    #expect(abs(dragDraft.radiusMeters - 0.019) < 1.0e-12)
    #expect(abs(dragDraft.startAngleRadians - (expectedEndAngle - span)) < 1.0e-12)
    #expect(abs(dragDraft.endAngleRadians - expectedEndAngle) < 1.0e-12)
}

@Test func canvasSplineClickDraftCreatesDefaultCubicBezier() throws {
    let center = Point2D(x: -0.04, y: 0.025)

    let draft = try CanvasSketchCurveDrafts.spline(centeredAt: center)

    #expect(pointsMatch(draft.controlPoints, [
        Point2D(x: -0.06, y: 0.025),
        Point2D(x: -0.046_666_666_666_666_67, y: 0.037),
        Point2D(x: -0.033_333_333_333_333_33, y: 0.037),
        Point2D(x: -0.02, y: 0.025),
    ]))
}

@Test func canvasSplineDragDraftCreatesBulgedCubicBezierBetweenEndpoints() throws {
    let start = Point2D(x: 0.0, y: 0.0)
    let end = Point2D(x: 0.03, y: 0.04)

    let draft = try CanvasSketchCurveDrafts.spline(from: start, to: end)

    #expect(pointsMatch(draft.controlPoints, [
        Point2D(x: 0.0, y: 0.0),
        Point2D(x: 0.0, y: 0.020_833_333_333_333_332),
        Point2D(x: 0.010_000_000_000_000_002, y: 0.034_166_666_666_666_665),
        Point2D(x: 0.03, y: 0.04),
    ]))
}

@Test func canvasPolygonDraftAppliesRadiusAndRotationOverrides() throws {
    let center = Point2D(x: -0.04, y: 0.025)
    let radiusPoint = Point2D(x: 0.04, y: 0.02)
    let rotation = Double.pi / 6.0

    let clickDraft = try CanvasSketchCurveDrafts.polygon(
        centeredAt: center,
        sides: 5,
        sizingMode: .circumradius,
        inclinationMode: .vertical,
        radiusMeters: 0.017,
        rotationAngleRadians: rotation
    )
    let dragDraft = try CanvasSketchCurveDrafts.polygon(
        fromCenter: center,
        toRadiusPoint: radiusPoint,
        sides: 5,
        sizingMode: .circumradius,
        inclinationMode: .vertical,
        radiusMeters: 0.019,
        rotationAngleRadians: rotation
    )

    #expect(abs(clickDraft.radiusMeters - 0.017) < 1.0e-12)
    #expect(abs(clickDraft.rotationAngleRadians - rotation) < 1.0e-12)
    #expect(abs(clickDraft.vertices[0].x - (center.x + cos(rotation) * 0.017)) < 1.0e-12)
    #expect(abs(clickDraft.vertices[0].y - (center.y + sin(rotation) * 0.017)) < 1.0e-12)
    #expect(abs(dragDraft.radiusMeters - 0.019) < 1.0e-12)
    #expect(abs(dragDraft.rotationAngleRadians - rotation) < 1.0e-12)
}

@Test func canvasCurveDraftsRejectInvalidInput() {
    do {
        _ = try CanvasSketchCurveDrafts.arc(
            centeredAt: Point2D(x: Double.nan, y: 0.0)
        )
        Issue.record("Non-finite arc placement must fail.")
    } catch let failure as CanvasSketchCurveDrafts.Failure {
        #expect(failure == .nonFiniteArcPlacement)
    } catch {
        Issue.record("Unexpected error: \(error)")
    }

    do {
        _ = try CanvasSketchCurveDrafts.arc(
            fromCenter: Point2D(x: 1.0, y: 1.0),
            toRadiusPoint: Point2D(x: 1.0, y: 1.0)
        )
        Issue.record("Degenerate arc drag must fail.")
    } catch let failure as CanvasSketchCurveDrafts.Failure {
        #expect(failure == .zeroArcRadius)
    } catch {
        Issue.record("Unexpected error: \(error)")
    }

    do {
        _ = try CanvasSketchCurveDrafts.arc(
            centeredAt: Point2D(x: 0.0, y: 0.0),
            spanAngleRadians: 0.0
        )
        Issue.record("Zero arc span input must fail.")
    } catch let failure as CanvasSketchCurveDrafts.Failure {
        #expect(failure == .invalidArcSpan)
    } catch {
        Issue.record("Unexpected error: \(error)")
    }

    do {
        _ = try CanvasSketchCurveDrafts.spline(
            from: Point2D(x: 1.0, y: 1.0),
            to: Point2D(x: 1.0, y: 1.0)
        )
        Issue.record("Degenerate spline drag must fail.")
    } catch let failure as CanvasSketchCurveDrafts.Failure {
        #expect(failure == .coincidentSplineEndpoints)
    } catch {
        Issue.record("Unexpected error: \(error)")
    }
}

private func pointsMatch(
    _ first: [Point2D],
    _ second: [Point2D],
    tolerance: Double = 1.0e-12
) -> Bool {
    guard first.count == second.count else {
        return false
    }
    return zip(first, second).allSatisfy { lhs, rhs in
        abs(lhs.x - rhs.x) <= tolerance
            && abs(lhs.y - rhs.y) <= tolerance
    }
}
