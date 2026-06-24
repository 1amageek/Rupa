import Foundation
import SwiftCAD

public enum PatternArrayOutputMode: String, Codable, Hashable, Sendable {
    case componentInstance
}

public enum PatternArrayDistanceMode: String, Codable, Hashable, Sendable {
    case spacing
    case extent
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

public enum PatternArrayDistribution: Codable, Hashable, Sendable {
    case rectangular(RectangularPatternArray)

    public func validate(tolerance: ModelingTolerance = .standard) throws {
        switch self {
        case .rectangular(let rectangular):
            try rectangular.validate(tolerance: tolerance)
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
