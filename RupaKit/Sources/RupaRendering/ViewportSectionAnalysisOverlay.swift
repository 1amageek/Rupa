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

    public var plane: PlaneItem?
    public var segments: [SegmentItem]
    public var sourceSegmentCount: Int
    public var omittedSegmentCount: Int
    public var hasTruncatedSourcePayload: Bool

    public init(
        plane: PlaneItem? = nil,
        segments: [SegmentItem] = [],
        sourceSegmentCount: Int = 0,
        omittedSegmentCount: Int = 0,
        hasTruncatedSourcePayload: Bool = false
    ) {
        self.plane = plane
        self.segments = segments
        self.sourceSegmentCount = sourceSegmentCount
        self.omittedSegmentCount = omittedSegmentCount
        self.hasTruncatedSourcePayload = hasTruncatedSourcePayload
    }

    public static func build(
        result: SectionAnalysisResult?,
        document: DesignDocument,
        maximumVisibleSegments: Int = 2_048
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
        let planeItem = planeItem(
            for: result,
            ruler: ruler
        )
        return ViewportSectionAnalysisOverlay(
            plane: planeItem,
            segments: segmentItems,
            sourceSegmentCount: result.intersectionSegments.count,
            omittedSegmentCount: max(0, result.intersectionSegments.count - segmentItems.count),
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
