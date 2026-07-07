import CoreGraphics
import RupaCore
import RupaViewportScene
import SwiftCAD

struct ViewportPlacementPreviewGeometry: Equatable {
    enum Shape: Equatable {
        case rectangle(ViewportProjectedRect)
        case polygon(center: CGPoint, vertices: [CGPoint], radiusEnd: CGPoint)
        case arc(center: CGPoint, points: [CGPoint], radiusEnd: CGPoint)
        case spline(controlPoints: [CGPoint], curvePoints: [CGPoint])
        case circle(center: CGPoint, points: [CGPoint], radiusEnd: CGPoint)
    }

    var shape: Shape

    init?(
        placement: ViewportPlacementHighlight,
        layout: ViewportLayout,
        defaults: WorkspaceScaleDefaults,
        visibleCellMeters: Double
    ) {
        guard let projection = Projection(sketchPlane: placement.sketchPlane) else {
            return nil
        }
        let center = projection.localPoint(fromCanvas: placement.point)
        switch placement.previewKind {
        case .rectangle(let widthOverride, let heightOverride, let fallback):
            let fallbackSide: Double
            switch fallback {
            case .workspaceDefault:
                fallbackSide = defaults.placedRectangleWidthMeters
            case .visibleCell:
                fallbackSide = visibleCellMeters.isFinite && visibleCellMeters > 0.0
                    ? visibleCellMeters
                    : defaults.placedSolidSideMeters
            }
            let width = widthOverride ?? fallbackSide
            let fallbackHeight: Double
            switch fallback {
            case .workspaceDefault:
                fallbackHeight = defaults.placedRectangleHeightMeters
            case .visibleCell:
                fallbackHeight = fallbackSide
            }
            let height = heightOverride ?? fallbackHeight
            guard width.isFinite, width > 0.0, height.isFinite, height > 0.0 else {
                return nil
            }
            let halfWidth = width / 2.0
            let halfHeight = height / 2.0
            guard let bottomLeft = projection.project(
                localPoint: Point2D(x: center.x - halfWidth, y: center.y - halfHeight),
                layout: layout
            ),
            let bottomRight = projection.project(
                localPoint: Point2D(x: center.x + halfWidth, y: center.y - halfHeight),
                layout: layout
            ),
            let topRight = projection.project(
                localPoint: Point2D(x: center.x + halfWidth, y: center.y + halfHeight),
                layout: layout
            ),
            let topLeft = projection.project(
                localPoint: Point2D(x: center.x - halfWidth, y: center.y + halfHeight),
                layout: layout
            ) else {
                return nil
            }
            shape = .rectangle(
                ViewportProjectedRect(
                    bottomLeft: bottomLeft,
                    bottomRight: bottomRight,
                    topRight: topRight,
                    topLeft: topLeft
                )
            )
        case .polygon(let state, let radiusMeters, let rotationAngleRadians):
            let draft: CanvasSketchCurveDrafts.Polygon
            do {
                draft = try CanvasSketchCurveDrafts.polygon(
                    centeredAt: center,
                    sides: state.sideCount,
                    sizingMode: state.sizingMode,
                    inclinationMode: state.inclinationMode,
                    defaults: defaults,
                    radiusMeters: radiusMeters,
                    rotationAngleRadians: rotationAngleRadians
                )
            } catch {
                return nil
            }
            guard let projectedCenter = projection.project(localPoint: draft.center, layout: layout),
            let radiusEnd = projection.project(
                localPoint: Point2D(
                    x: draft.center.x + cos(draft.rotationAngleRadians) * draft.circumradiusMeters,
                    y: draft.center.y + sin(draft.rotationAngleRadians) * draft.circumradiusMeters
                ),
                layout: layout
            ) else {
                return nil
            }
            let vertices = draft.vertices.compactMap { projection.project(localPoint: $0, layout: layout) }
            guard vertices.count == draft.vertices.count else {
                return nil
            }
            shape = .polygon(center: projectedCenter, vertices: vertices, radiusEnd: radiusEnd)
        case .arc(let radiusMeters, let spanAngleRadians):
            let draft: CanvasSketchCurveDrafts.Arc
            do {
                draft = try CanvasSketchCurveDrafts.arc(
                    centeredAt: center,
                    defaults: defaults,
                    radiusMeters: radiusMeters,
                    spanAngleRadians: spanAngleRadians
                )
            } catch {
                return nil
            }
            guard let projectedCenter = projection.project(localPoint: draft.center, layout: layout),
            let radiusEnd = projection.project(
                localPoint: Point2D(
                    x: draft.center.x + cos(draft.endAngleRadians) * draft.radiusMeters,
                    y: draft.center.y + sin(draft.endAngleRadians) * draft.radiusMeters
                ),
                layout: layout
            ) else {
                return nil
            }
            let points = Self.arcSamplePoints(
                center: CGPoint(x: draft.center.x, y: draft.center.y),
                radiusMeters: draft.radiusMeters,
                startAngleRadians: draft.startAngleRadians,
                endAngleRadians: draft.endAngleRadians,
                segmentCount: 24
            ).compactMap {
                projection.project(localPoint: Point2D(x: Double($0.x), y: Double($0.y)), layout: layout)
            }
            guard points.count == 25 else {
                return nil
            }
            shape = .arc(center: projectedCenter, points: points, radiusEnd: radiusEnd)
        case .spline:
            let draft: CanvasSketchCurveDrafts.Spline
            do {
                draft = try CanvasSketchCurveDrafts.spline(centeredAt: center, defaults: defaults)
            } catch {
                return nil
            }
            let curvePoints = Self.cubicBezierSamplePoints(
                controlPoints: draft.controlPoints,
                segmentCount: 32
            )
            let projectedControlPoints = draft.controlPoints.compactMap {
                projection.project(localPoint: $0, layout: layout)
            }
            let projectedCurvePoints = curvePoints.compactMap {
                projection.project(localPoint: Point2D(x: Double($0.x), y: Double($0.y)), layout: layout)
            }
            guard projectedControlPoints.count == draft.controlPoints.count,
                  projectedCurvePoints.count == curvePoints.count else {
                return nil
            }
            shape = .spline(controlPoints: projectedControlPoints, curvePoints: projectedCurvePoints)
        case .circle(let radiusMeters):
            let radius = radiusMeters ?? defaults.curveRadiusMeters
            guard radius.isFinite, radius > 0.0,
                  let projectedCenter = projection.project(localPoint: center, layout: layout),
                  let radiusEnd = projection.project(
                      localPoint: Point2D(x: center.x + radius, y: center.y),
                      layout: layout
                  ) else {
                return nil
            }
            let points = (0 ... 48).compactMap { index in
                let angle = Double(index) / 48.0 * Double.pi * 2.0
                return projection.project(
                    localPoint: Point2D(
                        x: center.x + cos(angle) * radius,
                        y: center.y + sin(angle) * radius
                    ),
                    layout: layout
                )
            }
            guard points.count == 49 else {
                return nil
            }
            shape = .circle(center: projectedCenter, points: points, radiusEnd: radiusEnd)
        }
    }

    private static func arcSamplePoints(
        center: CGPoint,
        radiusMeters: Double,
        startAngleRadians: Double,
        endAngleRadians: Double,
        segmentCount: Int
    ) -> [CGPoint] {
        let radius = max(CGFloat(radiusMeters), 1.0e-12)
        let span = normalizedArcSpan(startAngle: startAngleRadians, endAngle: endAngleRadians)
        let count = max(segmentCount, 2)
        return (0 ... count).map { index in
            let ratio = Double(index) / Double(count)
            let angle = startAngleRadians + span * ratio
            return CGPoint(
                x: center.x + cos(CGFloat(angle)) * radius,
                y: center.y + sin(CGFloat(angle)) * radius
            )
        }
    }

    private static func normalizedArcSpan(startAngle: Double, endAngle: Double) -> Double {
        let fullCircle = Double.pi * 2.0
        let tolerance = 1.0e-12
        var span = endAngle - startAngle
        while span <= tolerance {
            span += fullCircle
        }
        while span > fullCircle + tolerance {
            span -= fullCircle
        }
        return min(span, fullCircle)
    }

    private static func cubicBezierSamplePoints(
        controlPoints: [Point2D],
        segmentCount: Int
    ) -> [CGPoint] {
        guard controlPoints.count == 4 else {
            return []
        }
        let count = max(segmentCount, 2)
        return (0 ... count).map { index in
            let t = Double(index) / Double(count)
            let inverse = 1.0 - t
            let first = inverse * inverse * inverse
            let second = 3.0 * inverse * inverse * t
            let third = 3.0 * inverse * t * t
            let fourth = t * t * t
            return CGPoint(
                x: CGFloat(controlPoints[0].x * first
                    + controlPoints[1].x * second
                    + controlPoints[2].x * third
                    + controlPoints[3].x * fourth),
                y: CGFloat(controlPoints[0].y * first
                    + controlPoints[1].y * second
                    + controlPoints[2].y * third
                    + controlPoints[3].y * fourth)
            )
        }
    }

    private struct Projection {
        private var coordinateSystem: SketchPlaneCoordinateSystem
        private var canvasMapper: SketchPlaneCanvasMapper

        init?(sketchPlane: SketchPlane) {
            do {
                coordinateSystem = try SketchPlaneCoordinateSystem(plane: sketchPlane)
                canvasMapper = SketchPlaneCanvasMapper(sketchPlane: sketchPlane)
            } catch {
                return nil
            }
        }

        func localPoint(fromCanvas point: Point2D) -> Point2D {
            canvasMapper.localPoint(fromCanvas: point)
        }

        func project(localPoint: Point2D, layout: ViewportLayout) -> CGPoint? {
            guard localPoint.x.isFinite, localPoint.y.isFinite else {
                return nil
            }
            return layout.project(coordinateSystem.point(from: localPoint))
        }
    }
}
