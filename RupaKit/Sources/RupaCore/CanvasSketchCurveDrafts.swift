import Foundation
import SwiftCAD

public enum CanvasSketchCurveDrafts {
    public struct Arc: Equatable, Sendable {
        public let center: Point2D
        public let radiusMeters: Double
        public let startAngleRadians: Double
        public let endAngleRadians: Double

        public init(
            center: Point2D,
            radiusMeters: Double,
            startAngleRadians: Double,
            endAngleRadians: Double
        ) {
            self.center = center
            self.radiusMeters = radiusMeters
            self.startAngleRadians = startAngleRadians
            self.endAngleRadians = endAngleRadians
        }
    }

    public struct Spline: Equatable, Sendable {
        public let controlPoints: [Point2D]

        public init(controlPoints: [Point2D]) {
            self.controlPoints = controlPoints
        }
    }

    public struct Polygon: Equatable, Sendable {
        public let center: Point2D
        public let radiusMeters: Double
        public let sizingMode: PolygonSizingMode
        public let inclinationMode: PolygonInclinationMode
        public let circumradiusMeters: Double
        public let sides: Int
        public let rotationAngleRadians: Double
        public let vertices: [Point2D]

        public init(
            center: Point2D,
            radiusMeters: Double,
            sizingMode: PolygonSizingMode,
            inclinationMode: PolygonInclinationMode,
            circumradiusMeters: Double,
            sides: Int,
            rotationAngleRadians: Double,
            vertices: [Point2D]
        ) {
            self.center = center
            self.radiusMeters = radiusMeters
            self.sizingMode = sizingMode
            self.inclinationMode = inclinationMode
            self.circumradiusMeters = circumradiusMeters
            self.sides = sides
            self.rotationAngleRadians = rotationAngleRadians
            self.vertices = vertices
        }
    }

    public enum Failure: Swift.Error, Equatable, Sendable {
        case nonFiniteArcPlacement
        case nonFiniteArcDrag
        case zeroArcRadius
        case nonFiniteSplinePlacement
        case nonFiniteSplineDrag
        case coincidentSplineEndpoints
        case invalidArcSpan
        case nonFinitePolygonRotation
        case nonFinitePolygonPlacement
        case nonFinitePolygonDrag
        case invalidPolygonSides
        case zeroPolygonRadius

        public var message: String {
            switch self {
            case .nonFiniteArcPlacement:
                "Canvas arc placement requires a finite model coordinate."
            case .nonFiniteArcDrag:
                "Canvas arc drag requires finite model coordinates."
            case .zeroArcRadius:
                "Canvas arc drag requires a non-zero radius."
            case .nonFiniteSplinePlacement:
                "Canvas spline placement requires a finite model coordinate."
            case .nonFiniteSplineDrag:
                "Canvas spline drag requires finite model coordinates."
            case .coincidentSplineEndpoints:
                "Canvas spline drag requires distinct start and end coordinates."
            case .invalidArcSpan:
                "Canvas arc angle input must be greater than zero and less than a full circle."
            case .nonFinitePolygonRotation:
                "Canvas polygon angle input requires a finite value."
            case .nonFinitePolygonPlacement:
                "Canvas polygon placement requires a finite model coordinate."
            case .nonFinitePolygonDrag:
                "Canvas polygon drag requires finite model coordinates."
            case .invalidPolygonSides:
                "Canvas polygon requires between 3 and 256 sides."
            case .zeroPolygonRadius:
                "Canvas polygon drag requires a non-zero radius."
            }
        }
    }

    public static func arc(
        centeredAt center: Point2D,
        radiusMeters radiusOverrideMeters: Double? = nil,
        spanAngleRadians spanAngleOverrideRadians: Double? = nil
    ) throws -> Arc {
        guard isFinite(center) else {
            throw Failure.nonFiniteArcPlacement
        }
        let radius = try resolvedRadius(
            override: radiusOverrideMeters,
            fallback: LengthDisplayUnit.millimeter.meters(from: 12.0),
            failure: .zeroArcRadius
        )
        let spanAngle = try resolvedArcSpanAngle(
            spanAngleOverrideRadians ?? Double.pi / 2.0
        )
        return Arc(
            center: center,
            radiusMeters: radius,
            startAngleRadians: 0.0,
            endAngleRadians: spanAngle
        )
    }

    public static func arc(
        fromCenter center: Point2D,
        toRadiusPoint radiusPoint: Point2D,
        radiusMeters radiusOverrideMeters: Double? = nil,
        spanAngleRadians spanAngleOverrideRadians: Double? = nil
    ) throws -> Arc {
        guard isFinite(center), isFinite(radiusPoint) else {
            throw Failure.nonFiniteArcDrag
        }

        let deltaX = radiusPoint.x - center.x
        let deltaY = radiusPoint.y - center.y
        let radius = try resolvedRadius(
            override: radiusOverrideMeters,
            fallback: sqrt(deltaX * deltaX + deltaY * deltaY),
            failure: .zeroArcRadius
        )

        let endAngle = atan2(deltaY, deltaX)
        let spanAngle = try resolvedArcSpanAngle(
            spanAngleOverrideRadians ?? Double.pi / 2.0
        )
        return Arc(
            center: center,
            radiusMeters: radius,
            startAngleRadians: endAngle - spanAngle,
            endAngleRadians: endAngle
        )
    }

    public static func spline(centeredAt center: Point2D) throws -> Spline {
        guard isFinite(center) else {
            throw Failure.nonFiniteSplinePlacement
        }

        let halfWidth = LengthDisplayUnit.millimeter.meters(from: 20.0)
        let bow = LengthDisplayUnit.millimeter.meters(from: 12.0)
        return Spline(controlPoints: [
            Point2D(x: center.x - halfWidth, y: center.y),
            Point2D(x: center.x - halfWidth / 3.0, y: center.y + bow),
            Point2D(x: center.x + halfWidth / 3.0, y: center.y + bow),
            Point2D(x: center.x + halfWidth, y: center.y),
        ])
    }

    public static func spline(
        from start: Point2D,
        to end: Point2D
    ) throws -> Spline {
        guard isFinite(start), isFinite(end) else {
            throw Failure.nonFiniteSplineDrag
        }

        let deltaX = end.x - start.x
        let deltaY = end.y - start.y
        let length = sqrt(deltaX * deltaX + deltaY * deltaY)
        guard length.isFinite, length > minimumDistanceMeters else {
            throw Failure.coincidentSplineEndpoints
        }

        let normalX = -deltaY / length
        let normalY = deltaX / length
        let bow = min(length * 0.25, LengthDisplayUnit.millimeter.meters(from: 24.0))
        return Spline(controlPoints: [
            start,
            Point2D(
                x: start.x + deltaX / 3.0 + normalX * bow,
                y: start.y + deltaY / 3.0 + normalY * bow
            ),
            Point2D(
                x: start.x + deltaX * 2.0 / 3.0 + normalX * bow,
                y: start.y + deltaY * 2.0 / 3.0 + normalY * bow
            ),
            end,
        ])
    }

    public static func polygon(
        centeredAt center: Point2D,
        sides: Int = defaultPolygonSides,
        sizingMode: PolygonSizingMode = .circumradius,
        inclinationMode: PolygonInclinationMode = .vertical,
        radiusMeters radiusOverrideMeters: Double? = nil,
        rotationAngleRadians rotationAngleOverrideRadians: Double? = nil
    ) throws -> Polygon {
        guard isFinite(center) else {
            throw Failure.nonFinitePolygonPlacement
        }
        try validatePolygonSides(sides)

        let radius = try resolvedRadius(
            override: radiusOverrideMeters,
            fallback: LengthDisplayUnit.millimeter.meters(from: 12.0),
            failure: .zeroPolygonRadius
        )
        let circumradius = sizingMode.circumradius(from: radius, sides: sides)
        let rotationAngle = try resolvedPolygonRotationAngle(
            override: rotationAngleOverrideRadians,
            inclinationMode: inclinationMode,
            sizingMode: sizingMode,
            sides: sides
        )
        return Polygon(
            center: center,
            radiusMeters: radius,
            sizingMode: sizingMode,
            inclinationMode: inclinationMode,
            circumradiusMeters: circumradius,
            sides: sides,
            rotationAngleRadians: rotationAngle,
            vertices: polygonVertices(
                center: center,
                radiusMeters: circumradius,
                sides: sides,
                rotationAngleRadians: rotationAngle
            )
        )
    }

    public static func polygon(
        fromCenter center: Point2D,
        toRadiusPoint radiusPoint: Point2D,
        sides: Int = defaultPolygonSides,
        sizingMode: PolygonSizingMode = .circumradius,
        inclinationMode: PolygonInclinationMode = .vertical,
        radiusMeters radiusOverrideMeters: Double? = nil,
        rotationAngleRadians rotationAngleOverrideRadians: Double? = nil
    ) throws -> Polygon {
        guard isFinite(center), isFinite(radiusPoint) else {
            throw Failure.nonFinitePolygonDrag
        }
        try validatePolygonSides(sides)

        let deltaX = radiusPoint.x - center.x
        let deltaY = radiusPoint.y - center.y
        let radius = try resolvedRadius(
            override: radiusOverrideMeters,
            fallback: sqrt(deltaX * deltaX + deltaY * deltaY),
            failure: .zeroPolygonRadius
        )
        let circumradius = sizingMode.circumradius(from: radius, sides: sides)
        let rotationAngle = try resolvedPolygonRotationAngle(
            override: rotationAngleOverrideRadians,
            inclinationMode: inclinationMode,
            sizingMode: sizingMode,
            sides: sides
        )
        return Polygon(
            center: center,
            radiusMeters: radius,
            sizingMode: sizingMode,
            inclinationMode: inclinationMode,
            circumradiusMeters: circumradius,
            sides: sides,
            rotationAngleRadians: rotationAngle,
            vertices: polygonVertices(
                center: center,
                radiusMeters: circumradius,
                sides: sides,
                rotationAngleRadians: rotationAngle
            )
        )
    }

    public static let defaultPolygonSides = 6

    private static let minimumDistanceMeters = 1.0e-9
    private static let minimumAngleRadians = 1.0e-12

    private static func isFinite(_ point: Point2D) -> Bool {
        point.x.isFinite && point.y.isFinite
    }

    private static func resolvedRadius(
        override radiusOverrideMeters: Double?,
        fallback: Double,
        failure: Failure
    ) throws -> Double {
        let radius = radiusOverrideMeters ?? fallback
        guard radius.isFinite, radius > minimumDistanceMeters else {
            throw failure
        }
        return radius
    }

    private static func resolvedArcSpanAngle(_ angleRadians: Double) throws -> Double {
        guard angleRadians.isFinite,
              angleRadians > minimumAngleRadians,
              angleRadians < Double.pi * 2.0 - minimumAngleRadians else {
            throw Failure.invalidArcSpan
        }
        return angleRadians
    }

    private static func resolvedPolygonRotationAngle(
        override rotationAngleOverrideRadians: Double?,
        inclinationMode: PolygonInclinationMode,
        sizingMode: PolygonSizingMode,
        sides: Int
    ) throws -> Double {
        guard let rotationAngleOverrideRadians else {
            return inclinationMode.rotationAngleRadians(
                sides: sides,
                sizingMode: sizingMode
            )
        }
        guard rotationAngleOverrideRadians.isFinite else {
            throw Failure.nonFinitePolygonRotation
        }
        return rotationAngleOverrideRadians
    }

    private static func validatePolygonSides(_ sides: Int) throws {
        guard sides >= 3, sides <= 256 else {
            throw Failure.invalidPolygonSides
        }
    }

    private static func polygonVertices(
        center: Point2D,
        radiusMeters: Double,
        sides: Int,
        rotationAngleRadians: Double
    ) -> [Point2D] {
        (0..<sides).map { index in
            let angle = rotationAngleRadians + Double(index) * 2.0 * Double.pi / Double(sides)
            return Point2D(
                x: center.x + cos(angle) * radiusMeters,
                y: center.y + sin(angle) * radiusMeters
            )
        }
    }
}
