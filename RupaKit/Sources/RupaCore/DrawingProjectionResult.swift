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

    public enum SectionHatchPattern: String, Codable, Equatable, Sendable {
        case linear
        case radial
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

    public struct SectionContour: Codable, Equatable, Sendable {
        public var id: String
        public var sectionSourceID: String?
        public var sectionSourceName: String?
        public var bodyID: String
        public var points: [Point3D]
        public var sectionPlanePoints2D: [Point2D]
        public var projectedPoints2D: [Point2D]
        public var signedAreaSquareMeters: Double
        public var lengthMeters: Double
        public var segmentCount: Int

        public init(
            id: String,
            sectionSourceID: String?,
            sectionSourceName: String?,
            bodyID: String,
            points: [Point3D],
            sectionPlanePoints2D: [Point2D],
            projectedPoints2D: [Point2D],
            signedAreaSquareMeters: Double,
            lengthMeters: Double,
            segmentCount: Int
        ) {
            self.id = id
            self.sectionSourceID = sectionSourceID
            self.sectionSourceName = sectionSourceName
            self.bodyID = bodyID
            self.points = points
            self.sectionPlanePoints2D = sectionPlanePoints2D
            self.projectedPoints2D = projectedPoints2D
            self.signedAreaSquareMeters = signedAreaSquareMeters
            self.lengthMeters = lengthMeters
            self.segmentCount = segmentCount
        }
    }

    public struct SectionHatchSegment: Codable, Equatable, Sendable {
        public var id: String
        public var contourID: String
        public var sectionSourceID: String?
        public var sectionSourceName: String?
        public var bodyID: String
        public var start: Point3D
        public var end: Point3D
        public var start2D: Point2D
        public var end2D: Point2D
        public var pattern: SectionHatchPattern
        public var spacingMeters: Double
        public var angleDegrees: Double
        public var lengthMeters: Double

        public init(
            id: String,
            contourID: String,
            sectionSourceID: String?,
            sectionSourceName: String?,
            bodyID: String,
            start: Point3D,
            end: Point3D,
            start2D: Point2D,
            end2D: Point2D,
            pattern: SectionHatchPattern = .linear,
            spacingMeters: Double,
            angleDegrees: Double,
            lengthMeters: Double
        ) {
            self.id = id
            self.contourID = contourID
            self.sectionSourceID = sectionSourceID
            self.sectionSourceName = sectionSourceName
            self.bodyID = bodyID
            self.start = start
            self.end = end
            self.start2D = start2D
            self.end2D = end2D
            self.pattern = pattern
            self.spacingMeters = spacingMeters
            self.angleDegrees = angleDegrees
            self.lengthMeters = lengthMeters
        }
    }

    public struct AnnotationAnchor: Codable, Equatable, Sendable {
        public var role: MeasurementAnchor.Role
        public var kind: MeasurementAnchor.Kind
        public var worldPoint: Point3D
        public var point2D: Point2D

        public init(
            role: MeasurementAnchor.Role,
            kind: MeasurementAnchor.Kind,
            worldPoint: Point3D,
            point2D: Point2D
        ) {
            self.role = role
            self.kind = kind
            self.worldPoint = worldPoint
            self.point2D = point2D
        }
    }

    public enum AnnotationLabelPlacement: String, Codable, Equatable, Sendable {
        case manual
        case automatic
        case adjusted
    }

    public struct AnnotationLabelLayout: Codable, Equatable, Sendable {
        public var placement: AnnotationLabelPlacement
        public var bounds2D: Bounds2D
        public var leaderStart2D: Point2D?
        public var leaderEnd2D: Point2D?
        public var priorityIndex: Int

        public init(
            placement: AnnotationLabelPlacement,
            bounds2D: Bounds2D,
            leaderStart2D: Point2D? = nil,
            leaderEnd2D: Point2D? = nil,
            priorityIndex: Int
        ) {
            self.placement = placement
            self.bounds2D = bounds2D
            self.leaderStart2D = leaderStart2D
            self.leaderEnd2D = leaderEnd2D
            self.priorityIndex = priorityIndex
        }
    }

    public struct Annotation: Codable, Equatable, Sendable {
        public var id: String
        public var measurementID: MeasurementAnnotationID
        public var sceneNodeID: SceneNodeID?
        public var name: String
        public var kind: MeasurementAnnotation.Kind
        public var anchors: [AnnotationAnchor]
        public var labelWorldPoint: Point3D?
        public var labelPoint2D: Point2D
        public var measurementMeters: Double?
        public var measurementSquareMeters: Double?
        public var measurementDegrees: Double?
        public var displayText: String
        public var labelLayout: AnnotationLabelLayout?

        public init(
            id: String,
            measurementID: MeasurementAnnotationID,
            sceneNodeID: SceneNodeID?,
            name: String,
            kind: MeasurementAnnotation.Kind,
            anchors: [AnnotationAnchor],
            labelWorldPoint: Point3D?,
            labelPoint2D: Point2D,
            measurementMeters: Double? = nil,
            measurementSquareMeters: Double? = nil,
            measurementDegrees: Double? = nil,
            displayText: String,
            labelLayout: AnnotationLabelLayout? = nil
        ) {
            self.id = id
            self.measurementID = measurementID
            self.sceneNodeID = sceneNodeID
            self.name = name
            self.kind = kind
            self.anchors = anchors
            self.labelWorldPoint = labelWorldPoint
            self.labelPoint2D = labelPoint2D
            self.measurementMeters = measurementMeters
            self.measurementSquareMeters = measurementSquareMeters
            self.measurementDegrees = measurementDegrees
            self.displayText = displayText
            self.labelLayout = labelLayout
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
    public var sectionContourCount: Int
    public var sectionHatchSegmentCount: Int
    public var truncatedSectionHatches: Bool
    public var sectionContours: [SectionContour]
    public var sectionHatches: [SectionHatchSegment]
    public var annotationCount: Int
    public var annotations: [Annotation]
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
        sectionContours: [SectionContour] = [],
        sectionHatches: [SectionHatchSegment] = [],
        truncatedSectionHatches: Bool = false,
        annotations: [Annotation] = [],
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
        self.sectionContourCount = sectionContours.count
        self.sectionHatchSegmentCount = sectionHatches.count
        self.truncatedSectionHatches = truncatedSectionHatches
        self.sectionContours = sectionContours
        self.sectionHatches = sectionHatches
        self.annotationCount = annotations.count
        self.annotations = annotations
        self.diagnostics = diagnostics
    }

    private enum CodingKeys: String, CodingKey {
        case displayUnit
        case savedViewID
        case savedViewName
        case projectionMode
        case viewFrame
        case bodyCount
        case triangleCount
        case candidateEdgeCount
        case strokeCount
        case visibleStrokeCount
        case hiddenStrokeCount
        case partiallyHiddenStrokeCount
        case unclassifiedStrokeCount
        case visibilitySegmentCount
        case visibleSegmentCount
        case hiddenSegmentCount
        case partiallyHiddenSegmentCount
        case unclassifiedSegmentCount
        case truncatedStrokes
        case bounds
        case strokes
        case sectionContourCount
        case sectionHatchSegmentCount
        case truncatedSectionHatches
        case sectionContours
        case sectionHatches
        case annotationCount
        case annotations
        case diagnostics
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            displayUnit: try container.decode(LengthDisplayUnit.self, forKey: .displayUnit),
            savedViewID: try container.decode(SavedViewID.self, forKey: .savedViewID),
            savedViewName: try container.decode(String.self, forKey: .savedViewName),
            projectionMode: try container.decode(ProjectionMode.self, forKey: .projectionMode),
            viewFrame: try container.decode(ViewFrame.self, forKey: .viewFrame),
            bodyCount: try container.decode(Int.self, forKey: .bodyCount),
            triangleCount: try container.decode(Int.self, forKey: .triangleCount),
            candidateEdgeCount: try container.decode(Int.self, forKey: .candidateEdgeCount),
            truncatedStrokes: try container.decode(Bool.self, forKey: .truncatedStrokes),
            bounds: try container.decodeIfPresent(Bounds2D.self, forKey: .bounds),
            strokes: try container.decode([Stroke].self, forKey: .strokes),
            sectionContours: try container.decodeIfPresent(
                [SectionContour].self,
                forKey: .sectionContours
            ) ?? [],
            sectionHatches: try container.decodeIfPresent(
                [SectionHatchSegment].self,
                forKey: .sectionHatches
            ) ?? [],
            truncatedSectionHatches: try container.decodeIfPresent(
                Bool.self,
                forKey: .truncatedSectionHatches
            ) ?? false,
            annotations: try container.decodeIfPresent(
                [Annotation].self,
                forKey: .annotations
            ) ?? [],
            diagnostics: try container.decode([EditorDiagnostic].self, forKey: .diagnostics)
        )
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(displayUnit, forKey: .displayUnit)
        try container.encode(savedViewID, forKey: .savedViewID)
        try container.encode(savedViewName, forKey: .savedViewName)
        try container.encode(projectionMode, forKey: .projectionMode)
        try container.encode(viewFrame, forKey: .viewFrame)
        try container.encode(bodyCount, forKey: .bodyCount)
        try container.encode(triangleCount, forKey: .triangleCount)
        try container.encode(candidateEdgeCount, forKey: .candidateEdgeCount)
        try container.encode(strokeCount, forKey: .strokeCount)
        try container.encode(visibleStrokeCount, forKey: .visibleStrokeCount)
        try container.encode(hiddenStrokeCount, forKey: .hiddenStrokeCount)
        try container.encode(partiallyHiddenStrokeCount, forKey: .partiallyHiddenStrokeCount)
        try container.encode(unclassifiedStrokeCount, forKey: .unclassifiedStrokeCount)
        try container.encode(visibilitySegmentCount, forKey: .visibilitySegmentCount)
        try container.encode(visibleSegmentCount, forKey: .visibleSegmentCount)
        try container.encode(hiddenSegmentCount, forKey: .hiddenSegmentCount)
        try container.encode(partiallyHiddenSegmentCount, forKey: .partiallyHiddenSegmentCount)
        try container.encode(unclassifiedSegmentCount, forKey: .unclassifiedSegmentCount)
        try container.encode(truncatedStrokes, forKey: .truncatedStrokes)
        try container.encodeIfPresent(bounds, forKey: .bounds)
        try container.encode(strokes, forKey: .strokes)
        try container.encode(sectionContourCount, forKey: .sectionContourCount)
        try container.encode(sectionHatchSegmentCount, forKey: .sectionHatchSegmentCount)
        try container.encode(truncatedSectionHatches, forKey: .truncatedSectionHatches)
        try container.encode(sectionContours, forKey: .sectionContours)
        try container.encode(sectionHatches, forKey: .sectionHatches)
        try container.encode(annotationCount, forKey: .annotationCount)
        try container.encode(annotations, forKey: .annotations)
        try container.encode(diagnostics, forKey: .diagnostics)
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
