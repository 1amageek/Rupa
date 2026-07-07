import RupaCore
import SwiftCAD

public enum ViewportCanvasPlacementPreviewKind: Equatable, Sendable {
    case rectangle(widthMeters: Double?, heightMeters: Double?, fallback: RectangleFallback)
    case polygon(PolygonToolState, radiusMeters: Double?, rotationAngleRadians: Double?)
    case arc(radiusMeters: Double?, spanAngleRadians: Double?)
    case spline
    case circle(radiusMeters: Double?)

    public enum RectangleFallback: Equatable, Sendable {
        case workspaceDefault
        case visibleCell
    }
}

struct ViewportPlacementHighlight: Equatable, Sendable {
    var point: Point2D
    var sketchPlane: SketchPlane
    var previewKind: ViewportCanvasPlacementPreviewKind
}
