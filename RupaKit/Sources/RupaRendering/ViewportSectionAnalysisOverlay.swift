import Foundation
import RupaCore

public struct ViewportSectionAnalysisOverlay: Equatable {
    public struct PlaneItem: Equatable, Identifiable {
        public var id: String
        public var sourceKind: SectionAnalysisResult.PlaneSourceKind
        public var sourceID: String?
        public var sourceName: String?
        public var origin: Point3D
        public var normalEnd: Point3D
        public var corners: [Point3D]
        public var halfExtentMeters: Double

        public init(
            id: String,
            sourceKind: SectionAnalysisResult.PlaneSourceKind,
            sourceID: String?,
            sourceName: String?,
            origin: Point3D,
            normalEnd: Point3D,
            corners: [Point3D],
            halfExtentMeters: Double
        ) {
            self.id = id
            self.sourceKind = sourceKind
            self.sourceID = sourceID
            self.sourceName = sourceName
            self.origin = origin
            self.normalEnd = normalEnd
            self.corners = corners
            self.halfExtentMeters = halfExtentMeters
        }
    }

    public struct SegmentItem: Equatable, Identifiable {
        public var id: String
        public var bodyID: String
        public var start: Point3D
        public var end: Point3D

        public init(
            id: String,
            bodyID: String,
            start: Point3D,
            end: Point3D
        ) {
            self.id = id
            self.bodyID = bodyID
            self.start = start
            self.end = end
        }
    }

    public struct ContourItem: Equatable, Identifiable {
        public var id: String
        public var bodyID: String
        public var points: [Point3D]
        public var points2D: [Point2D]
        public var isClosed: Bool
        public var signedAreaSquareMeters: Double

        public init(
            id: String,
            bodyID: String,
            points: [Point3D],
            points2D: [Point2D],
            isClosed: Bool,
            signedAreaSquareMeters: Double
        ) {
            self.id = id
            self.bodyID = bodyID
            self.points = points
            self.points2D = points2D
            self.isClosed = isClosed
            self.signedAreaSquareMeters = signedAreaSquareMeters
        }
    }

    public struct HatchItem: Equatable, Identifiable {
        public var id: String
        public var contourID: String
        public var start: Point3D
        public var end: Point3D

        public init(
            id: String,
            contourID: String,
            start: Point3D,
            end: Point3D
        ) {
            self.id = id
            self.contourID = contourID
            self.start = start
            self.end = end
        }
    }

    public var plane: PlaneItem?
    public var segments: [SegmentItem]
    public var contours: [ContourItem]
    public var hatches: [HatchItem]
    public var sourceSegmentCount: Int
    public var omittedSegmentCount: Int
    public var sourceContourCount: Int
    public var omittedContourCount: Int
    public var hasTruncatedSourcePayload: Bool

    public init(
        plane: PlaneItem? = nil,
        segments: [SegmentItem] = [],
        contours: [ContourItem] = [],
        hatches: [HatchItem] = [],
        sourceSegmentCount: Int = 0,
        omittedSegmentCount: Int = 0,
        sourceContourCount: Int = 0,
        omittedContourCount: Int = 0,
        hasTruncatedSourcePayload: Bool = false
    ) {
        self.plane = plane
        self.segments = segments
        self.contours = contours
        self.hatches = hatches
        self.sourceSegmentCount = sourceSegmentCount
        self.omittedSegmentCount = omittedSegmentCount
        self.sourceContourCount = sourceContourCount
        self.omittedContourCount = omittedContourCount
        self.hasTruncatedSourcePayload = hasTruncatedSourcePayload
    }

    public static func build(
        result: SectionAnalysisResult?,
        document: DesignDocument,
        maximumVisibleSegments: Int = 2_048,
        maximumVisibleContours: Int = 128,
        maximumVisibleHatches: Int = 512
    ) -> ViewportSectionAnalysisOverlay {
        guard let result else {
            return ViewportSectionAnalysisOverlay()
        }
        let ruler = document.ruler.normalizedForWorkspaceScale()
        let visibleLimit = max(0, maximumVisibleSegments)
        let visibleSegments = result.intersectionSegments.prefix(visibleLimit)
        let segmentItems = visibleSegments.enumerated().map { index, segment in
            SegmentItem(
                id: "\(segment.bodyID):section:\(index)",
                bodyID: segment.bodyID,
                start: segment.start,
                end: segment.end
            )
        }
        let visibleContourLimit = max(0, maximumVisibleContours)
        let contourItems = result.intersectionContours.prefix(visibleContourLimit).map { contour in
            ContourItem(
                id: contour.id,
                bodyID: contour.bodyID,
                points: contour.points,
                points2D: contour.points2D,
                isClosed: contour.isClosed,
                signedAreaSquareMeters: contour.signedAreaSquareMeters
            )
        }
        let hatchItems = hatches(
            for: contourItems,
            plane: result.plane,
            ruler: ruler,
            tolerance: result.toleranceMeters,
            maximumVisibleHatches: maximumVisibleHatches
        )
        let planeItem = planeItem(
            for: result,
            ruler: ruler
        )
        return ViewportSectionAnalysisOverlay(
            plane: planeItem,
            segments: segmentItems,
            contours: contourItems,
            hatches: hatchItems,
            sourceSegmentCount: result.intersectionSegments.count,
            omittedSegmentCount: max(0, result.intersectionSegments.count - segmentItems.count),
            sourceContourCount: result.intersectionContours.count,
            omittedContourCount: max(0, result.intersectionContours.count - contourItems.count),
            hasTruncatedSourcePayload: result.truncatedIntersectionSegments
        )
    }

    private static func planeItem(
        for result: SectionAnalysisResult,
        ruler: RulerConfiguration
    ) -> PlaneItem {
        let halfExtent = planeHalfExtentMeters(
            result: result,
            ruler: ruler
        )
        let plane = result.plane
        let origin = plane.origin
        let normalGuideLength = max(
            ruler.majorTickMeters,
            min(ruler.visibleSpanMeters * 0.08, halfExtent * 0.28)
        )
        let normalEnd = point(
            origin,
            offsetBy: plane.normal,
            scaledBy: normalGuideLength
        )
        let negativeUNegativeV = point(
            point(origin, offsetBy: plane.u, scaledBy: -halfExtent),
            offsetBy: plane.v,
            scaledBy: -halfExtent
        )
        let positiveUNegativeV = point(
            point(origin, offsetBy: plane.u, scaledBy: halfExtent),
            offsetBy: plane.v,
            scaledBy: -halfExtent
        )
        let positiveUPositiveV = point(
            point(origin, offsetBy: plane.u, scaledBy: halfExtent),
            offsetBy: plane.v,
            scaledBy: halfExtent
        )
        let negativeUPositiveV = point(
            point(origin, offsetBy: plane.u, scaledBy: -halfExtent),
            offsetBy: plane.v,
            scaledBy: halfExtent
        )
        let corners = [
            negativeUNegativeV,
            positiveUNegativeV,
            positiveUPositiveV,
            negativeUPositiveV,
        ]
        return PlaneItem(
            id: plane.sourceID ?? "\(plane.sourceKind.rawValue):section-plane",
            sourceKind: plane.sourceKind,
            sourceID: plane.sourceID,
            sourceName: plane.sourceName,
            origin: origin,
            normalEnd: normalEnd,
            corners: corners,
            halfExtentMeters: halfExtent
        )
    }

    private static func point(
        _ origin: Point3D,
        offsetBy vector: Vector3D,
        scaledBy scale: Double
    ) -> Point3D {
        Point3D(
            x: origin.x + vector.x * scale,
            y: origin.y + vector.y * scale,
            z: origin.z + vector.z * scale
        )
    }

    private static func hatches(
        for contours: [ContourItem],
        plane: SectionAnalysisResult.Plane,
        ruler: RulerConfiguration,
        tolerance: Double,
        maximumVisibleHatches: Int
    ) -> [HatchItem] {
        var items: [HatchItem] = []
        items.reserveCapacity(max(0, maximumVisibleHatches))
        for contour in contours where contour.isClosed && contour.points2D.count >= 3 {
            let remaining = maximumVisibleHatches - items.count
            guard remaining > 0 else {
                break
            }
            items.append(contentsOf: hatches(
                for: contour,
                plane: plane,
                ruler: ruler,
                tolerance: tolerance,
                maximumCount: remaining
            ))
        }
        return items
    }

    private static func hatches(
        for contour: ContourItem,
        plane: SectionAnalysisResult.Plane,
        ruler: RulerConfiguration,
        tolerance: Double,
        maximumCount: Int
    ) -> [HatchItem] {
        guard let bounds = bounds(for: contour.points2D), maximumCount > 0 else {
            return []
        }
        let width = max(bounds.maxX - bounds.minX, tolerance)
        let height = max(bounds.maxY - bounds.minY, tolerance)
        let span = max(width, height)
        var step = max(
            tolerance * 16.0,
            min(max(ruler.majorTickMeters * 0.2, ruler.minorTickMeters), span / 10.0)
        )
        let estimatedLineCount = Int(ceil(height / step)) + 1
        if estimatedLineCount > maximumCount {
            step = max(height / Double(maximumCount), tolerance * 16.0)
        }

        var hatches: [HatchItem] = []
        var y = ceil(bounds.minY / step) * step
        var hatchIndex = 0
        while y <= bounds.maxY && hatches.count < maximumCount {
            let intersections = scanlineIntersections(
                y: y,
                polygon: contour.points2D,
                tolerance: tolerance
            )
            var pairIndex = 0
            while pairIndex + 1 < intersections.count && hatches.count < maximumCount {
                let startX = intersections[pairIndex]
                let endX = intersections[pairIndex + 1]
                if endX - startX > tolerance {
                    hatches.append(HatchItem(
                        id: "\(contour.id):hatch:\(hatchIndex)",
                        contourID: contour.id,
                        start: point(on: plane, x: startX, y: y),
                        end: point(on: plane, x: endX, y: y)
                    ))
                    hatchIndex += 1
                }
                pairIndex += 2
            }
            y += step
        }
        return hatches
    }

    private static func bounds(
        for points: [Point2D]
    ) -> (minX: Double, maxX: Double, minY: Double, maxY: Double)? {
        guard let first = points.first else {
            return nil
        }
        return points.dropFirst().reduce(
            (minX: first.x, maxX: first.x, minY: first.y, maxY: first.y)
        ) { result, point in
            (
                minX: min(result.minX, point.x),
                maxX: max(result.maxX, point.x),
                minY: min(result.minY, point.y),
                maxY: max(result.maxY, point.y)
            )
        }
    }

    private static func scanlineIntersections(
        y: Double,
        polygon: [Point2D],
        tolerance: Double
    ) -> [Double] {
        guard polygon.count >= 3 else {
            return []
        }
        var intersections: [Double] = []
        for index in polygon.indices {
            let start = polygon[index]
            let end = polygon[(index + 1) % polygon.count]
            let crosses = (start.y <= y && end.y > y) || (end.y <= y && start.y > y)
            guard crosses else {
                continue
            }
            let dy = end.y - start.y
            guard abs(dy) > tolerance else {
                continue
            }
            let t = (y - start.y) / dy
            guard t.isFinite else {
                continue
            }
            intersections.append(start.x + (end.x - start.x) * t)
        }
        return intersections.sorted()
    }

    private static func point(
        on plane: SectionAnalysisResult.Plane,
        x: Double,
        y: Double
    ) -> Point3D {
        Point3D(
            x: plane.origin.x + plane.u.x * x + plane.v.x * y,
            y: plane.origin.y + plane.u.y * x + plane.v.y * y,
            z: plane.origin.z + plane.u.z * x + plane.v.z * y
        )
    }

    private static func planeHalfExtentMeters(
        result: SectionAnalysisResult,
        ruler: RulerConfiguration
    ) -> Double {
        let minimumVisibleExtent = max(
            ruler.majorTickMeters * 2.0,
            ruler.visibleSpanMeters * 0.04,
            result.toleranceMeters * 64.0
        )
        let segmentExtent = result.intersectionSegments.reduce(0.0) { extent, segment in
            max(
                extent,
                abs(segment.start2D.x),
                abs(segment.start2D.y),
                abs(segment.end2D.x),
                abs(segment.end2D.y)
            )
        }
        return max(minimumVisibleExtent, segmentExtent + ruler.majorTickMeters)
    }
}
