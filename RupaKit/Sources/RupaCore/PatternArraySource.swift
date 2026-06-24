import Foundation
import SwiftCAD

public enum PatternArrayOutputMode: String, Codable, Hashable, Sendable {
    case componentInstance
}

public enum PatternArrayDistanceMode: String, Codable, Hashable, Sendable {
    case spacing
    case extent
}

public enum PatternArrayAngleMode: String, Codable, Hashable, Sendable {
    case spacing
    case extent
}

public enum PatternArrayCurveAlignment: String, Codable, Hashable, Sendable {
    case normal
    case parallel
    case transport
}

public enum PatternArrayCurveExtentMode: String, Codable, Hashable, Sendable {
    case distance
    case ratio
}

public struct PatternArrayGenerationBudget: Codable, Hashable, Sendable {
    public var maximumOutputInstanceCount: Int

    public init(maximumOutputInstanceCount: Int = 10_000) {
        self.maximumOutputInstanceCount = maximumOutputInstanceCount
    }

    public static let standard = PatternArrayGenerationBudget()

    public func validate() throws {
        guard maximumOutputInstanceCount > 0 else {
            throw DocumentValidationError.invalidProductMetadata(
                "Pattern array generation budget must allow at least one output instance."
            )
        }
    }
}

public struct PatternArrayLinearAxis: Codable, Hashable, Sendable {
    public var direction: Vector3D
    public var distance: CADExpression
    public var copyCount: Int
    public var distanceMode: PatternArrayDistanceMode

    public init(
        direction: Vector3D,
        distance: CADExpression,
        copyCount: Int,
        distanceMode: PatternArrayDistanceMode = .spacing
    ) {
        self.direction = direction
        self.distance = distance
        self.copyCount = copyCount
        self.distanceMode = distanceMode
    }

    public func validate(tolerance: ModelingTolerance = .standard) throws {
        try tolerance.validate()
        try direction.validate()
        guard direction.length > tolerance.distance else {
            throw DocumentValidationError.invalidProductMetadata(
                "Pattern array axis direction must be non-zero."
            )
        }
        guard copyCount > 0 else {
            throw DocumentValidationError.invalidProductMetadata(
                "Pattern array axis copy count must be positive."
            )
        }
        try distance.validateLiteralQuantities()
    }
}

public struct RectangularPatternArray: Codable, Hashable, Sendable {
    public var firstAxis: PatternArrayLinearAxis
    public var secondAxis: PatternArrayLinearAxis?

    public init(
        firstAxis: PatternArrayLinearAxis,
        secondAxis: PatternArrayLinearAxis? = nil
    ) {
        self.firstAxis = firstAxis
        self.secondAxis = secondAxis
    }

    public func validate(tolerance: ModelingTolerance = .standard) throws {
        try firstAxis.validate(tolerance: tolerance)
        try secondAxis?.validate(tolerance: tolerance)
        if let secondAxis {
            let firstDirection = try firstAxis.direction.normalized(tolerance: tolerance.distance)
            let secondDirection = try secondAxis.direction.normalized(tolerance: tolerance.distance)
            guard firstDirection.cross(secondDirection).length > tolerance.angle else {
                throw DocumentValidationError.invalidProductMetadata(
                    "Rectangular pattern array axes must not be parallel."
                )
            }
        }
    }
}

public struct PatternArrayAngularAxis: Codable, Hashable, Sendable {
    public var center: Point3D
    public var axis: Vector3D
    public var angle: CADExpression
    public var copyCount: Int
    public var angleMode: PatternArrayAngleMode

    public init(
        center: Point3D,
        axis: Vector3D,
        angle: CADExpression,
        copyCount: Int,
        angleMode: PatternArrayAngleMode = .spacing
    ) {
        self.center = center
        self.axis = axis
        self.angle = angle
        self.copyCount = copyCount
        self.angleMode = angleMode
    }

    public func validate(tolerance: ModelingTolerance = .standard) throws {
        try tolerance.validate()
        try center.validate()
        try axis.validate()
        guard axis.length > tolerance.distance else {
            throw DocumentValidationError.invalidProductMetadata(
                "Pattern array angular axis direction must be non-zero."
            )
        }
        guard copyCount > 0 else {
            throw DocumentValidationError.invalidProductMetadata(
                "Pattern array angular copy count must be positive."
            )
        }
        try angle.validateLiteralQuantities()
    }
}

public struct RadialPatternArray: Codable, Hashable, Sendable {
    public var angularAxis: PatternArrayAngularAxis
    public var radialAxis: PatternArrayLinearAxis?

    public init(
        angularAxis: PatternArrayAngularAxis,
        radialAxis: PatternArrayLinearAxis? = nil
    ) {
        self.angularAxis = angularAxis
        self.radialAxis = radialAxis
    }

    public func validate(tolerance: ModelingTolerance = .standard) throws {
        try angularAxis.validate(tolerance: tolerance)
        try radialAxis?.validate(tolerance: tolerance)
        if let radialAxis {
            let axis = try angularAxis.axis.normalized(tolerance: tolerance.distance)
            let radialDirection = try radialAxis.direction.normalized(tolerance: tolerance.distance)
            guard axis.cross(radialDirection).length > tolerance.angle else {
                throw DocumentValidationError.invalidProductMetadata(
                    "Radial pattern array repetition direction must not be parallel to the rotation axis."
                )
            }
        }
    }
}

public enum PatternArrayCurvePath: Codable, Hashable, Sendable {
    case polyline(points: [Point3D], normal: Vector3D?)
    case sketchEntity(featureID: FeatureID, entityID: SketchEntityID)

    public func validate(tolerance: ModelingTolerance = .standard) throws {
        try tolerance.validate()
        switch self {
        case .polyline(let points, let normal):
            guard points.count >= 2 else {
                throw DocumentValidationError.invalidProductMetadata(
                    "Curve pattern array polyline paths must contain at least two points."
                )
            }
            for point in points {
                try point.validate()
            }
            for index in 1 ..< points.count {
                guard (points[index] - points[index - 1]).length > tolerance.distance else {
                    throw DocumentValidationError.invalidProductMetadata(
                        "Curve pattern array polyline paths must not contain degenerate spans."
                    )
                }
            }
            if let normal {
                try normal.validate()
                guard normal.length > tolerance.distance else {
                    throw DocumentValidationError.invalidProductMetadata(
                        "Curve pattern array path normal must be non-zero."
                    )
                }
            }
        case .sketchEntity:
            break
        }
    }
}

public struct CurvePatternArray: Codable, Hashable, Sendable {
    public var path: PatternArrayCurvePath
    public var copyCount: Int
    public var twist: CADExpression
    public var endScale: CADExpression
    public var alignment: PatternArrayCurveAlignment
    public var extent: CADExpression
    public var extentMode: PatternArrayCurveExtentMode

    public init(
        path: PatternArrayCurvePath,
        copyCount: Int,
        twist: CADExpression = .angle(0.0, .radian),
        endScale: CADExpression = .scalar(1.0),
        alignment: PatternArrayCurveAlignment = .transport,
        extent: CADExpression = .scalar(1.0),
        extentMode: PatternArrayCurveExtentMode = .ratio
    ) {
        self.path = path
        self.copyCount = copyCount
        self.twist = twist
        self.endScale = endScale
        self.alignment = alignment
        self.extent = extent
        self.extentMode = extentMode
    }

    public func validate(tolerance: ModelingTolerance = .standard) throws {
        try tolerance.validate()
        try path.validate(tolerance: tolerance)
        guard copyCount > 0 else {
            throw DocumentValidationError.invalidProductMetadata(
                "Curve pattern array copy count must be positive."
            )
        }
        try twist.validateLiteralQuantities()
        try endScale.validateLiteralQuantities()
        try extent.validateLiteralQuantities()
    }
}

public enum PatternArrayDistribution: Codable, Hashable, Sendable {
    case rectangular(RectangularPatternArray)
    case radial(RadialPatternArray)
    case curve(CurvePatternArray)

    public func validate(tolerance: ModelingTolerance = .standard) throws {
        switch self {
        case .rectangular(let rectangular):
            try rectangular.validate(tolerance: tolerance)
        case .radial(let radial):
            try radial.validate(tolerance: tolerance)
        case .curve(let curve):
            try curve.validate(tolerance: tolerance)
        }
    }
}

public struct PatternArraySource: Codable, Hashable, Identifiable, Sendable {
    public var id: PatternArraySourceID
    public var name: String
    public var definitionID: ComponentDefinitionID
    public var distribution: PatternArrayDistribution
    public var outputMode: PatternArrayOutputMode
    public var outputInstanceIDs: [ComponentInstanceID]
    public var rootSceneNodeID: SceneNodeID

    public init(
        id: PatternArraySourceID = PatternArraySourceID(),
        name: String,
        definitionID: ComponentDefinitionID,
        distribution: PatternArrayDistribution,
        outputMode: PatternArrayOutputMode = .componentInstance,
        outputInstanceIDs: [ComponentInstanceID] = [],
        rootSceneNodeID: SceneNodeID
    ) {
        self.id = id
        self.name = name
        self.definitionID = definitionID
        self.distribution = distribution
        self.outputMode = outputMode
        self.outputInstanceIDs = outputInstanceIDs
        self.rootSceneNodeID = rootSceneNodeID
    }

    public func validate(tolerance: ModelingTolerance = .standard) throws {
        guard !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw DocumentValidationError.invalidProductMetadata("Pattern array source names must not be empty.")
        }
        guard Set(outputInstanceIDs).count == outputInstanceIDs.count else {
            throw DocumentValidationError.invalidProductMetadata(
                "Pattern array output instance references must be unique."
            )
        }
        guard !outputInstanceIDs.isEmpty else {
            throw DocumentValidationError.invalidProductMetadata(
                "Pattern array sources must own at least one output instance."
            )
        }
        try distribution.validate(tolerance: tolerance)
    }
}
