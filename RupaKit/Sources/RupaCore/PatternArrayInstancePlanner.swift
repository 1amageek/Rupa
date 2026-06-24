import Foundation
import SwiftCAD

public struct PatternArrayInstancePlanner: Sendable {
    public init() {}

    public func transforms(
        for distribution: PatternArrayDistribution,
        parameters: ParameterTable,
        tolerance: ModelingTolerance = .standard,
        budget: PatternArrayGenerationBudget = .standard
    ) throws -> [Transform3D] {
        try tolerance.validate()
        try budget.validate()
        switch distribution {
        case .rectangular(let rectangular):
            return try rectangularTransforms(
                for: rectangular,
                parameters: parameters,
                tolerance: tolerance,
                budget: budget
            )
        }
    }

    private func rectangularTransforms(
        for rectangular: RectangularPatternArray,
        parameters: ParameterTable,
        tolerance: ModelingTolerance,
        budget: PatternArrayGenerationBudget
    ) throws -> [Transform3D] {
        try rectangular.validate(tolerance: tolerance)
        let outputCount = try rectangularOutputCount(for: rectangular)
        guard outputCount <= budget.maximumOutputInstanceCount else {
            throw EditorError(
                code: .commandInvalid,
                message: "Pattern array output count exceeds the generation budget."
            )
        }
        let firstStep = try stepVector(
            for: rectangular.firstAxis,
            parameters: parameters,
            tolerance: tolerance
        )
        guard let secondAxis = rectangular.secondAxis else {
            return try (1 ... rectangular.firstAxis.copyCount).map { firstIndex in
                try translationTransform(firstStep * Double(firstIndex))
            }
        }

        let secondStep = try stepVector(
            for: secondAxis,
            parameters: parameters,
            tolerance: tolerance
        )
        var transforms: [Transform3D] = []
        transforms.reserveCapacity(outputCount)
        for secondIndex in 0 ... secondAxis.copyCount {
            for firstIndex in 0 ... rectangular.firstAxis.copyCount {
                guard firstIndex != 0 || secondIndex != 0 else {
                    continue
                }
                let offset = firstStep * Double(firstIndex) + secondStep * Double(secondIndex)
                transforms.append(try translationTransform(offset))
            }
        }
        return transforms
    }

    private func rectangularOutputCount(
        for rectangular: RectangularPatternArray
    ) throws -> Int {
        guard let secondAxis = rectangular.secondAxis else {
            return rectangular.firstAxis.copyCount
        }
        let firstAdded = rectangular.firstAxis.copyCount.addingReportingOverflow(1)
        let secondAdded = secondAxis.copyCount.addingReportingOverflow(1)
        guard !firstAdded.overflow,
              !secondAdded.overflow else {
            throw EditorError(
                code: .commandInvalid,
                message: "Pattern array output count exceeds the generation budget."
            )
        }
        let firstTerm = firstAdded.partialValue
        let secondTerm = secondAdded.partialValue
        let multiplied = firstTerm.multipliedReportingOverflow(by: secondTerm)
        guard !multiplied.overflow,
              multiplied.partialValue > 0 else {
            throw EditorError(
                code: .commandInvalid,
                message: "Pattern array output count exceeds the generation budget."
            )
        }
        return multiplied.partialValue - 1
    }

    private func stepVector(
        for axis: PatternArrayLinearAxis,
        parameters: ParameterTable,
        tolerance: ModelingTolerance
    ) throws -> Vector3D {
        try axis.validate(tolerance: tolerance)
        let distance = try resolvedLength(
            axis.distance,
            parameters: parameters
        )
        guard distance.isFinite,
              abs(distance) > tolerance.distance else {
            throw EditorError(
                code: .commandInvalid,
                message: "Pattern array axis distance must resolve to a non-zero finite length."
            )
        }
        let normalizedDirection = try axis.direction.normalized(tolerance: tolerance.distance)
        let stepDistance: Double
        switch axis.distanceMode {
        case .spacing:
            stepDistance = distance
        case .extent:
            stepDistance = distance / Double(axis.copyCount)
        }
        return normalizedDirection * stepDistance
    }

    private func resolvedLength(
        _ expression: CADExpression,
        parameters: ParameterTable
    ) throws -> Double {
        let quantity: Quantity
        do {
            quantity = try parameters.resolvedValue(for: expression)
        } catch let error as EditorError {
            throw error
        } catch {
            throw EditorError(
                code: .commandInvalid,
                message: "Pattern array distance could not be resolved: \(error)."
            )
        }
        guard quantity.kind == .length else {
            throw EditorError(
                code: .commandInvalid,
                message: "Pattern array distance must resolve to a length."
            )
        }
        return quantity.value
    }

    private func translationTransform(_ vector: Vector3D) throws -> Transform3D {
        var values = Matrix4x4.identity.values
        values[12] = vector.x
        values[13] = vector.y
        values[14] = vector.z
        return Transform3D(matrix: try Matrix4x4(values: values))
    }
}
