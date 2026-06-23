public struct SketchDisplaySnapshot: Equatable, Sendable {
    public struct Bounds: Equatable, Sendable {
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

    public enum Primitive: Equatable, Sendable {
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
        case spline(
            entityID: SketchEntityID,
            points: [Point2D],
            controlPoints: [Point2D],
            sketchPlane: SketchPlane
        )

        public var entityID: SketchEntityID {
            switch self {
            case .point(let entityID, _),
                 .line(let entityID, _, _),
                 .circle(let entityID, _, _),
                 .arc(let entityID, _, _, _, _),
                 .spline(let entityID, _, _, _):
                entityID
            }
        }
    }

    public struct Region: Equatable, Sendable {
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
