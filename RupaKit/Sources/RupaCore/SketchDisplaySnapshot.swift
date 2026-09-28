public struct SketchDisplaySnapshot: Codable, Equatable, Sendable {
    public struct Bounds: Codable, Equatable, Sendable {
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

        public var width: Double {
            maxX - minX
        }

        public var height: Double {
            maxY - minY
        }
    }

    public enum Primitive: Codable, Equatable, Sendable {
        case point(entityID: SketchEntityID, point: Point2D)
        case line(entityID: SketchEntityID, start: Point2D, end: Point2D)
        case circle(entityID: SketchEntityID, center: Point2D, radiusMeters: Double)
        case arc(
            entityID: SketchEntityID,
            center: Point2D,
            radiusMeters: Double,
            startAngleRadians: Double,
            endAngleRadians: Double
        )
        /// `points` are display samples; `controlPoints`, `degree` and `knots` (the resolved clamped
        /// knot vector) are the spline itself, for readers that evaluate or edit it.
        case spline(
            entityID: SketchEntityID,
            points: [Point2D],
            controlPoints: [Point2D],
            degree: Int,
            knots: [Double],
            sketchPlane: SketchPlane
        )

        /// A cubic Bezier chain spline primitive: 3n + 1 control points, knots of multiplicity 3
        /// at every joint. A count that is not 3n + 1 has no chain knots; reading its curve fails.
        public static func cubicSpline(
            entityID: SketchEntityID,
            points: [Point2D],
            controlPoints: [Point2D],
            sketchPlane: SketchPlane
        ) -> Primitive {
            let placeholder = SketchPoint(x: .length(0, .meter), y: .length(0, .meter))
            let chain = SketchSpline(controlPoints: Array(repeating: placeholder, count: controlPoints.count))
            return .spline(
                entityID: entityID,
                points: points,
                controlPoints: controlPoints,
                degree: 3,
                knots: chain.knotVector ?? [],
                sketchPlane: sketchPlane
            )
        }

        public var entityID: SketchEntityID {
            switch self {
            case .point(let entityID, _),
                 .line(let entityID, _, _),
                 .circle(let entityID, _, _),
                 .arc(let entityID, _, _, _, _),
                 .spline(let entityID, _, _, _, _, _):
                entityID
            }
        }
    }

    public struct Region: Codable, Equatable, Sendable {
        public var componentID: SelectionComponentID
        public var points: [Point2D]

        public init(
            componentID: SelectionComponentID,
            points: [Point2D]
        ) {
            self.componentID = componentID
            self.points = points
        }
    }

    public var featureID: FeatureID
    public var plane: SketchPlane
    public var bounds: Bounds
    public var primitives: [Primitive]
    public var regions: [Region]
    public var singleCircleProfileRadiusMeters: Double?
    public var straightOpenPathVector: Vector3D?

    public init(
        featureID: FeatureID,
        plane: SketchPlane,
        bounds: Bounds,
        primitives: [Primitive],
        regions: [Region],
        singleCircleProfileRadiusMeters: Double?,
        straightOpenPathVector: Vector3D?
    ) {
        self.featureID = featureID
        self.plane = plane
        self.bounds = bounds
        self.primitives = primitives
        self.regions = regions
        self.singleCircleProfileRadiusMeters = singleCircleProfileRadiusMeters
        self.straightOpenPathVector = straightOpenPathVector
    }
}
