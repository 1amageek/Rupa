import Foundation
import SwiftCAD
import RupaCoreTypes

public struct DrawingProjectionResult: Codable, Equatable, Sendable {
    public enum ProjectionMode: String, Codable, Equatable, Sendable {
        case orthographic
        case perspective
    }

    public enum StrokeKind: String, Codable, Equatable, Sendable {
        case boundary
        case crease
    }

    public enum Visibility: String, Codable, Equatable, Sendable {
        case visible
        case hidden
        case partiallyHidden
        case unclassified
    }

    public struct VisibilitySegment: Codable, Equatable, Sendable {
        public var id: String
        public var visibility: Visibility
        public var startFraction: Double
        public var endFraction: Double
        public var start2D: Point2D
        public var end2D: Point2D
        public var minimumDepthMeters: Double
        public var maximumDepthMeters: Double
        public var lengthMeters: Double

        public init(
            id: String,
            visibility: Visibility,
            startFraction: Double,
            endFraction: Double,
            start2D: Point2D,
            end2D: Point2D,
            minimumDepthMeters: Double,
            maximumDepthMeters: Double,
            lengthMeters: Double
        ) {
            self.id = id
            self.visibility = visibility
            self.startFraction = startFraction
            self.endFraction = endFraction
            self.start2D = start2D
            self.end2D = end2D
            self.minimumDepthMeters = minimumDepthMeters
            self.maximumDepthMeters = maximumDepthMeters
            self.lengthMeters = lengthMeters
        }
    }

    public struct ViewFrame: Codable, Equatable, Sendable {
        public var target: Point3D
        public var right: Vector3D
        public var up: Vector3D
        public var viewNormal: Vector3D
        public var visibleHeightMeters: Double
        public var scaleBarLengthMeters: Double

        public init(
            target: Point3D,
            right: Vector3D,
            up: Vector3D,
            viewNormal: Vector3D,
            visibleHeightMeters: Double,
            scaleBarLengthMeters: Double
        ) {
            self.target = target
            self.right = right
            self.up = up
            self.viewNormal = viewNormal
            self.visibleHeightMeters = visibleHeightMeters
            self.scaleBarLengthMeters = scaleBarLengthMeters
        }
    }

    public struct Bounds2D: Codable, Equatable, Sendable {
        public var minX: Double
        public var minY: Double
        public var maxX: Double
        public var maxY: Double

        public init(
            minX: Double,
            minY: Double,
            maxX: Double,
            maxY: Double
        ) {
            self.minX = minX
            self.minY = minY
            self.maxX = maxX
            self.maxY = maxY
        }
    }

    public struct Stroke: Codable, Equatable, Sendable {
        public var id: String
        public var bodyID: String
        public var kind: StrokeKind
        public var visibility: Visibility
        public var start: Point3D
        public var end: Point3D
        public var start2D: Point2D
        public var end2D: Point2D
        public var minimumDepthMeters: Double
        public var maximumDepthMeters: Double
        public var lengthMeters: Double
        public var visibilitySegments: [VisibilitySegment]

        public init(
            id: String,
            bodyID: String,
            kind: StrokeKind,
            visibility: Visibility,
            start: Point3D,
            end: Point3D,
            start2D: Point2D,
            end2D: Point2D,
            minimumDepthMeters: Double,
            maximumDepthMeters: Double,
            lengthMeters: Double,
            visibilitySegments: [VisibilitySegment]
        ) {
            self.id = id
            self.bodyID = bodyID
            self.kind = kind
            self.visibility = visibility
            self.start = start
            self.end = end
            self.start2D = start2D
            self.end2D = end2D
            self.minimumDepthMeters = minimumDepthMeters
            self.maximumDepthMeters = maximumDepthMeters
            self.lengthMeters = lengthMeters
            self.visibilitySegments = visibilitySegments
        }
    }

    public var displayUnit: LengthDisplayUnit
    public var savedViewID: SavedViewID
    public var savedViewName: String
    public var projectionMode: ProjectionMode
    public var viewFrame: ViewFrame
    public var bodyCount: Int
    public var triangleCount: Int
    public var candidateEdgeCount: Int
    public var strokeCount: Int
    public var visibleStrokeCount: Int
    public var hiddenStrokeCount: Int
    public var partiallyHiddenStrokeCount: Int
    public var unclassifiedStrokeCount: Int
    public var visibilitySegmentCount: Int
    public var visibleSegmentCount: Int
    public var hiddenSegmentCount: Int
    public var partiallyHiddenSegmentCount: Int
    public var unclassifiedSegmentCount: Int
    public var truncatedStrokes: Bool
    public var bounds: Bounds2D?
    public var strokes: [Stroke]
    public var diagnostics: [EditorDiagnostic]

    public init(
        displayUnit: LengthDisplayUnit,
        savedViewID: SavedViewID,
        savedViewName: String,
        projectionMode: ProjectionMode,
        viewFrame: ViewFrame,
        bodyCount: Int,
        triangleCount: Int,
        candidateEdgeCount: Int,
        truncatedStrokes: Bool,
        bounds: Bounds2D?,
        strokes: [Stroke],
        diagnostics: [EditorDiagnostic]
    ) {
        let visibilityCounts = Self.visibilityCounts(strokes)
        let visibilitySegmentCounts = Self.visibilitySegmentCounts(strokes)
        self.displayUnit = displayUnit
        self.savedViewID = savedViewID
        self.savedViewName = savedViewName
        self.projectionMode = projectionMode
        self.viewFrame = viewFrame
        self.bodyCount = bodyCount
        self.triangleCount = triangleCount
        self.candidateEdgeCount = candidateEdgeCount
        self.strokeCount = strokes.count
        self.visibleStrokeCount = visibilityCounts.visible
        self.hiddenStrokeCount = visibilityCounts.hidden
        self.partiallyHiddenStrokeCount = visibilityCounts.partiallyHidden
        self.unclassifiedStrokeCount = visibilityCounts.unclassified
        self.visibilitySegmentCount = visibilitySegmentCounts.total
        self.visibleSegmentCount = visibilitySegmentCounts.visible
        self.hiddenSegmentCount = visibilitySegmentCounts.hidden
        self.partiallyHiddenSegmentCount = visibilitySegmentCounts.partiallyHidden
        self.unclassifiedSegmentCount = visibilitySegmentCounts.unclassified
        self.truncatedStrokes = truncatedStrokes
        self.bounds = bounds
        self.strokes = strokes
        self.diagnostics = diagnostics
    }

    private static func visibilityCounts(
        _ strokes: [Stroke]
    ) -> (visible: Int, hidden: Int, partiallyHidden: Int, unclassified: Int) {
        var visible = 0
        var hidden = 0
        var partiallyHidden = 0
        var unclassified = 0
        for stroke in strokes {
            switch stroke.visibility {
            case .visible:
                visible += 1
            case .hidden:
                hidden += 1
            case .partiallyHidden:
                partiallyHidden += 1
            case .unclassified:
                unclassified += 1
            }
        }
        return (visible, hidden, partiallyHidden, unclassified)
    }

    private static func visibilitySegmentCounts(
        _ strokes: [Stroke]
    ) -> (total: Int, visible: Int, hidden: Int, partiallyHidden: Int, unclassified: Int) {
        var visible = 0
        var hidden = 0
        var partiallyHidden = 0
        var unclassified = 0
        var total = 0
        for stroke in strokes {
            for segment in stroke.visibilitySegments {
                total += 1
                switch segment.visibility {
                case .visible:
                    visible += 1
                case .hidden:
                    hidden += 1
                case .partiallyHidden:
                    partiallyHidden += 1
                case .unclassified:
                    unclassified += 1
                }
            }
        }
        return (total, visible, hidden, partiallyHidden, unclassified)
    }
}
