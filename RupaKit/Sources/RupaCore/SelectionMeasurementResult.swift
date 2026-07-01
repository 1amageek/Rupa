import Foundation
import SwiftCAD
import RupaCoreTypes

public enum SelectionMeasurementResult: Codable, Equatable, Sendable {
    case point(Point)
    case distance(Distance)
    case angle(Angle)

    private enum CodingKeys: String, CodingKey {
        case kind
        case point
        case distance
        case angle
    }

    private enum Kind: String, Codable {
        case point
        case distance
        case angle
    }

    public struct Point: Codable, Equatable, Sendable {
        public var selection: SelectionReference
        public var point: Point3D
        public var tangent: Vector3D?
        public var normal: Vector3D?
        public var curvature: Double?
        public var displayUnit: LengthDisplayUnit
        public var displayUnitSymbol: String
        public var displayPoint: Point3D
        public var displayCurvatureValue: Double?
        public var displayCurvatureUnitSymbol: String?

        private enum CodingKeys: String, CodingKey {
            case selection
            case point
            case tangent
            case normal
            case curvature
            case displayUnit
            case displayUnitSymbol
            case displayPoint
            case displayCurvatureValue
            case displayCurvatureUnitSymbol
        }

        public init(
            selection: SelectionReference,
            point: Point3D,
            tangent: Vector3D? = nil,
            normal: Vector3D? = nil,
            curvature: Double? = nil,
            displayUnit: LengthDisplayUnit
        ) {
            self.selection = selection
            self.point = point
            self.tangent = tangent
            self.normal = normal
            self.curvature = curvature
            self.displayUnit = displayUnit
            self.displayUnitSymbol = displayUnit.symbol
            self.displayPoint = Self.displayPoint(point, in: displayUnit)
            self.displayCurvatureValue = curvature.map { $0 * displayUnit.metersPerUnit }
            self.displayCurvatureUnitSymbol = curvature.map { _ in "1/\(displayUnit.symbol)" }
        }

        public init(
            measurement: SelectionMeasurementPoint,
            displayUnit: LengthDisplayUnit
        ) {
            self.init(
                selection: measurement.selection,
                point: measurement.point,
                tangent: measurement.tangent,
                normal: measurement.normal,
                curvature: measurement.curvature,
                displayUnit: displayUnit
            )
        }

        public init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            self.init(
                selection: try container.decode(SelectionReference.self, forKey: .selection),
                point: try container.decode(Point3D.self, forKey: .point),
                tangent: try container.decodeIfPresent(Vector3D.self, forKey: .tangent),
                normal: try container.decodeIfPresent(Vector3D.self, forKey: .normal),
                curvature: try container.decodeIfPresent(Double.self, forKey: .curvature),
                displayUnit: try container.decodeIfPresent(
                    LengthDisplayUnit.self,
                    forKey: .displayUnit
                ) ?? .meter
            )
        }

        private static func displayPoint(
            _ point: Point3D,
            in unit: LengthDisplayUnit
        ) -> Point3D {
            Point3D(
                x: unit.value(fromMeters: point.x),
                y: unit.value(fromMeters: point.y),
                z: unit.value(fromMeters: point.z)
            )
        }
    }

    public struct Distance: Codable, Equatable, Sendable {
        public var first: SelectionMeasurementPoint
        public var second: SelectionMeasurementPoint
        public var vector: Vector3D
        public var distance: Double
        public var displayUnit: LengthDisplayUnit
        public var displayUnitSymbol: String
        public var displayVector: Vector3D
        public var displayDistance: Double

        private enum CodingKeys: String, CodingKey {
            case first
            case second
            case vector
            case distance
            case displayUnit
            case displayUnitSymbol
            case displayVector
            case displayDistance
        }

        public init(
            first: SelectionMeasurementPoint,
            second: SelectionMeasurementPoint,
            vector: Vector3D,
            distance: Double,
            displayUnit: LengthDisplayUnit
        ) {
            self.first = first
            self.second = second
            self.vector = vector
            self.distance = distance
            self.displayUnit = displayUnit
            self.displayUnitSymbol = displayUnit.symbol
            self.displayVector = Self.displayVector(vector, in: displayUnit)
            self.displayDistance = displayUnit.value(fromMeters: distance)
        }

        public init(
            measurement: SelectionDistanceMeasurement,
            displayUnit: LengthDisplayUnit
        ) {
            self.init(
                first: measurement.first,
                second: measurement.second,
                vector: measurement.vector,
                distance: measurement.distance,
                displayUnit: displayUnit
            )
        }

        public init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            self.init(
                first: try container.decode(SelectionMeasurementPoint.self, forKey: .first),
                second: try container.decode(SelectionMeasurementPoint.self, forKey: .second),
                vector: try container.decode(Vector3D.self, forKey: .vector),
                distance: try container.decode(Double.self, forKey: .distance),
                displayUnit: try container.decodeIfPresent(
                    LengthDisplayUnit.self,
                    forKey: .displayUnit
                ) ?? .meter
            )
        }

        private static func displayVector(
            _ vector: Vector3D,
            in unit: LengthDisplayUnit
        ) -> Vector3D {
            Vector3D(
                x: unit.value(fromMeters: vector.x),
                y: unit.value(fromMeters: vector.y),
                z: unit.value(fromMeters: vector.z)
            )
        }
    }

    public struct Angle: Codable, Equatable, Sendable {
        public var first: SelectionMeasurementPoint
        public var second: SelectionMeasurementPoint
        public var firstDirection: Vector3D
        public var secondDirection: Vector3D
        public var angleRadians: Double
        public var angleDegrees: Double
        public var displayAngleValue: Double
        public var displayUnitSymbol: String

        private enum CodingKeys: String, CodingKey {
            case first
            case second
            case firstDirection
            case secondDirection
            case angleRadians
            case angleDegrees
            case displayAngleValue
            case displayUnitSymbol
        }

        public init(
            first: SelectionMeasurementPoint,
            second: SelectionMeasurementPoint,
            firstDirection: Vector3D,
            secondDirection: Vector3D,
            angleRadians: Double
        ) {
            self.first = first
            self.second = second
            self.firstDirection = firstDirection
            self.secondDirection = secondDirection
            self.angleRadians = angleRadians
            self.angleDegrees = angleRadians * 180.0 / Double.pi
            self.displayAngleValue = self.angleDegrees
            self.displayUnitSymbol = "deg"
        }

        public init(measurement: SelectionAngleMeasurement) {
            self.init(
                first: measurement.first,
                second: measurement.second,
                firstDirection: measurement.firstDirection,
                secondDirection: measurement.secondDirection,
                angleRadians: measurement.angleRadians
            )
        }

        public init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            self.init(
                first: try container.decode(SelectionMeasurementPoint.self, forKey: .first),
                second: try container.decode(SelectionMeasurementPoint.self, forKey: .second),
                firstDirection: try container.decode(Vector3D.self, forKey: .firstDirection),
                secondDirection: try container.decode(Vector3D.self, forKey: .secondDirection),
                angleRadians: try container.decode(Double.self, forKey: .angleRadians)
            )
        }
    }

    public init(
        rawValue: CADAgentMeasurementQueryResult,
        displayUnit: LengthDisplayUnit
    ) {
        switch rawValue {
        case .point(let point):
            self = .point(Point(measurement: point, displayUnit: displayUnit))
        case .distance(let distance):
            self = .distance(Distance(measurement: distance, displayUnit: displayUnit))
        case .angle(let angle):
            self = .angle(Angle(measurement: angle))
        }
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let kind = try container.decode(Kind.self, forKey: .kind)
        switch kind {
        case .point:
            self = .point(try container.decode(Point.self, forKey: .point))
        case .distance:
            self = .distance(try container.decode(Distance.self, forKey: .distance))
        case .angle:
            self = .angle(try container.decode(Angle.self, forKey: .angle))
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .point(let point):
            try container.encode(Kind.point, forKey: .kind)
            try container.encode(point, forKey: .point)
        case .distance(let distance):
            try container.encode(Kind.distance, forKey: .kind)
            try container.encode(distance, forKey: .distance)
        case .angle(let angle):
            try container.encode(Kind.angle, forKey: .kind)
            try container.encode(angle, forKey: .angle)
        }
    }
}
