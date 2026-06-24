import Foundation
import SwiftCAD

public struct PatternArrayInstancePlanner: Sendable {
    public init() {}

    public func transforms(
        for distribution: PatternArrayDistribution,
        parameters: ParameterTable,
        cadDocument: CADDocument? = nil,
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
        case .radial(let radial):
            return try radialTransforms(
                for: radial,
                parameters: parameters,
                tolerance: tolerance,
                budget: budget
            )
        case .curve(let curve):
            return try curveTransforms(
                for: curve,
                parameters: parameters,
                cadDocument: cadDocument,
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

    private func radialTransforms(
        for radial: RadialPatternArray,
        parameters: ParameterTable,
        tolerance: ModelingTolerance,
        budget: PatternArrayGenerationBudget
    ) throws -> [Transform3D] {
        try radial.validate(tolerance: tolerance)
        let outputCount = try radialOutputCount(for: radial)
        guard outputCount <= budget.maximumOutputInstanceCount else {
            throw EditorError(
                code: .commandInvalid,
                message: "Pattern array output count exceeds the generation budget."
            )
        }
        let stepAngle = try angularStep(
            for: radial.angularAxis,
            parameters: parameters,
            tolerance: tolerance
        )
        let radialStep = try radial.radialAxis.map {
            try stepVector(for: $0, parameters: parameters, tolerance: tolerance)
        }
        let rotationAxis = try radial.angularAxis.axis.normalized(tolerance: tolerance.distance)

        if let radialAxis = radial.radialAxis,
           let radialStep {
            var transforms: [Transform3D] = []
            transforms.reserveCapacity(outputCount)
            for radialIndex in 0 ... radialAxis.copyCount {
                for angularIndex in 0 ... radial.angularAxis.copyCount {
                    guard radialIndex != 0 || angularIndex != 0 else {
                        continue
                    }
                    transforms.append(
                        try radialTransform(
                            angle: stepAngle * Double(angularIndex),
                            axis: rotationAxis,
                            center: radial.angularAxis.center,
                            radialOffset: radialStep * Double(radialIndex)
                        )
                    )
                }
            }
            return transforms
        }

        return try (1 ... radial.angularAxis.copyCount).map { angularIndex in
            try radialTransform(
                angle: stepAngle * Double(angularIndex),
                axis: rotationAxis,
                center: radial.angularAxis.center,
                radialOffset: .zero
            )
        }
    }

    private func radialOutputCount(
        for radial: RadialPatternArray
    ) throws -> Int {
        guard let radialAxis = radial.radialAxis else {
            return radial.angularAxis.copyCount
        }
        let angularAdded = radial.angularAxis.copyCount.addingReportingOverflow(1)
        let radialAdded = radialAxis.copyCount.addingReportingOverflow(1)
        guard !angularAdded.overflow,
              !radialAdded.overflow else {
            throw EditorError(
                code: .commandInvalid,
                message: "Pattern array output count exceeds the generation budget."
            )
        }
        let multiplied = angularAdded.partialValue.multipliedReportingOverflow(by: radialAdded.partialValue)
        guard !multiplied.overflow,
              multiplied.partialValue > 0 else {
            throw EditorError(
                code: .commandInvalid,
                message: "Pattern array output count exceeds the generation budget."
            )
        }
        return multiplied.partialValue - 1
    }

    private func curveTransforms(
        for curve: CurvePatternArray,
        parameters: ParameterTable,
        cadDocument: CADDocument?,
        tolerance: ModelingTolerance,
        budget: PatternArrayGenerationBudget
    ) throws -> [Transform3D] {
        try curve.validate(tolerance: tolerance)
        guard curve.copyCount <= budget.maximumOutputInstanceCount else {
            throw EditorError(
                code: .commandInvalid,
                message: "Pattern array output count exceeds the generation budget."
            )
        }
        let geometry = try PatternArrayCurvePathGeometryService(
            tolerance: tolerance
        ).distributionGeometry(
            for: curve,
            parameters: parameters,
            cadDocument: cadDocument
        )
        let twist = try resolvedAngle(curve.twist, parameters: parameters)
        let endScale = try resolvedScalar(curve.endScale, parameters: parameters)
        guard endScale.isFinite,
              endScale > tolerance.distance else {
            throw EditorError(
                code: .commandInvalid,
                message: "Curve pattern array scale must resolve to a positive finite scalar."
            )
        }

        var transforms: [Transform3D] = []
        transforms.reserveCapacity(curve.copyCount)
        var transportFrame: CurvePatternFrame?
        for index in 1 ... curve.copyCount {
            let progress = Double(index) / Double(curve.copyCount)
            let sample = try geometry.path.sample(at: geometry.distributionLength * progress)
            let frame = try curveFrame(
                tangent: sample.tangent,
                referenceNormal: geometry.path.referenceNormal,
                alignment: curve.alignment,
                previousTransportFrame: &transportFrame,
                tolerance: tolerance
            )
            transforms.append(
                try curveTransform(
                    point: sample.point,
                    origin: geometry.path.origin,
                    frame: frame,
                    twist: twist * progress,
                    scale: 1.0 + (endScale - 1.0) * progress,
                    alignment: curve.alignment
                )
            )
        }
        return transforms
    }

    private func curveFrame(
        tangent: Vector3D,
        referenceNormal: Vector3D,
        alignment: PatternArrayCurveAlignment,
        previousTransportFrame: inout CurvePatternFrame?,
        tolerance: ModelingTolerance
    ) throws -> CurvePatternFrame {
        switch alignment {
        case .parallel:
            return CurvePatternFrame(
                tangent: .unitX,
                normal: .unitY,
                binormal: .unitZ
            )
        case .normal:
            return try normalCurveFrame(
                tangent: tangent,
                referenceNormal: referenceNormal,
                tolerance: tolerance
            )
        case .transport:
            let frame: CurvePatternFrame
            if let previousTransportFrame,
               let transportedNormal = try projectedUnitVector(
                previousTransportFrame.normal,
                perpendicularTo: tangent,
                tolerance: tolerance
               ) {
                let binormal = try tangent.cross(transportedNormal).normalized(tolerance: tolerance.distance)
                frame = CurvePatternFrame(
                    tangent: tangent,
                    normal: transportedNormal,
                    binormal: binormal
                )
            } else {
                frame = try normalCurveFrame(
                    tangent: tangent,
                    referenceNormal: referenceNormal,
                    tolerance: tolerance
                )
            }
            previousTransportFrame = frame
            return frame
        }
    }

    private func normalCurveFrame(
        tangent: Vector3D,
        referenceNormal: Vector3D,
        tolerance: ModelingTolerance
    ) throws -> CurvePatternFrame {
        let normal: Vector3D
        if let projectedNormal = try projectedUnitVector(
            referenceNormal,
            perpendicularTo: tangent,
            tolerance: tolerance
        ) {
            normal = projectedNormal
        } else {
            normal = try fallbackNormal(for: tangent, tolerance: tolerance)
        }
        let binormal = try tangent.cross(normal).normalized(tolerance: tolerance.distance)
        return CurvePatternFrame(
            tangent: tangent,
            normal: normal,
            binormal: binormal
        )
    }

    private func projectedUnitVector(
        _ vector: Vector3D,
        perpendicularTo axis: Vector3D,
        tolerance: ModelingTolerance
    ) throws -> Vector3D? {
        let projection = vector - axis * vector.dot(axis)
        guard projection.length > tolerance.distance else {
            return nil
        }
        return try projection.normalized(tolerance: tolerance.distance)
    }

    private func fallbackNormal(
        for tangent: Vector3D,
        tolerance: ModelingTolerance
    ) throws -> Vector3D {
        let helper = abs(tangent.z) < 0.9 ? Vector3D.unitZ : Vector3D.unitY
        let normal = helper - tangent * helper.dot(tangent)
        return try normal.normalized(tolerance: tolerance.distance)
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

    private func angularStep(
        for axis: PatternArrayAngularAxis,
        parameters: ParameterTable,
        tolerance: ModelingTolerance
    ) throws -> Double {
        try axis.validate(tolerance: tolerance)
        let angle = try resolvedAngle(axis.angle, parameters: parameters)
        guard angle.isFinite,
              abs(angle) > tolerance.angle else {
            throw EditorError(
                code: .commandInvalid,
                message: "Pattern array angle must resolve to a non-zero finite angle."
            )
        }
        switch axis.angleMode {
        case .spacing:
            return angle
        case .extent:
            return angle / Double(axis.copyCount)
        }
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

    private func resolvedAngle(
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
                message: "Pattern array angle could not be resolved: \(error)."
            )
        }
        guard quantity.kind == .angle else {
            throw EditorError(
                code: .commandInvalid,
                message: "Pattern array angle must resolve to an angle."
            )
        }
        return quantity.value
    }

    private func resolvedScalar(
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
                message: "Pattern array scalar value could not be resolved: \(error)."
            )
        }
        guard quantity.kind == .scalar else {
            throw EditorError(
                code: .commandInvalid,
                message: "Pattern array scalar value must resolve to a scalar."
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

    private func curveTransform(
        point: Point3D,
        origin: Point3D,
        frame: CurvePatternFrame,
        twist: Double,
        scale: Double,
        alignment: PatternArrayCurveAlignment
    ) throws -> Transform3D {
        let twistAxis: Vector3D
        switch alignment {
        case .parallel:
            twistAxis = .unitX
        case .normal, .transport:
            twistAxis = frame.tangent
        }
        let twistRotation = rotationValues(angle: twist, axis: twistAxis)
        let normal = rotated(frame.normal, rotation: twistRotation)
        let binormal = rotated(frame.binormal, rotation: twistRotation)
        let translation = point - origin
        return Transform3D(matrix: try Matrix4x4(values: [
            frame.tangent.x * scale, frame.tangent.y * scale, frame.tangent.z * scale, 0.0,
            normal.x * scale, normal.y * scale, normal.z * scale, 0.0,
            binormal.x * scale, binormal.y * scale, binormal.z * scale, 0.0,
            translation.x, translation.y, translation.z, 1.0,
        ]))
    }

    private func radialTransform(
        angle: Double,
        axis: Vector3D,
        center: Point3D,
        radialOffset: Vector3D
    ) throws -> Transform3D {
        let rotation = rotationValues(angle: angle, axis: axis)
        let centerVector = Vector3D(x: center.x, y: center.y, z: center.z)
        let rotatedCenter = rotated(centerVector, rotation: rotation)
        let rotatedOffset = rotated(radialOffset, rotation: rotation)
        let translation = centerVector - rotatedCenter + rotatedOffset
        return Transform3D(matrix: try Matrix4x4(values: [
            rotation.r00, rotation.r10, rotation.r20, 0.0,
            rotation.r01, rotation.r11, rotation.r21, 0.0,
            rotation.r02, rotation.r12, rotation.r22, 0.0,
            translation.x, translation.y, translation.z, 1.0,
        ]))
    }

    private func rotationValues(
        angle: Double,
        axis: Vector3D
    ) -> RotationValues {
        let sine = sin(angle)
        let cosine = cos(angle)
        let inverseCosine = 1.0 - cosine
        let x = axis.x
        let y = axis.y
        let z = axis.z
        return RotationValues(
            r00: cosine + x * x * inverseCosine,
            r01: x * y * inverseCosine - z * sine,
            r02: x * z * inverseCosine + y * sine,
            r10: y * x * inverseCosine + z * sine,
            r11: cosine + y * y * inverseCosine,
            r12: y * z * inverseCosine - x * sine,
            r20: z * x * inverseCosine - y * sine,
            r21: z * y * inverseCosine + x * sine,
            r22: cosine + z * z * inverseCosine
        )
    }

    private func rotated(
        _ vector: Vector3D,
        rotation: RotationValues
    ) -> Vector3D {
        Vector3D(
            x: rotation.r00 * vector.x + rotation.r01 * vector.y + rotation.r02 * vector.z,
            y: rotation.r10 * vector.x + rotation.r11 * vector.y + rotation.r12 * vector.z,
            z: rotation.r20 * vector.x + rotation.r21 * vector.y + rotation.r22 * vector.z
        )
    }

    private struct CurvePatternFrame: Sendable {
        var tangent: Vector3D
        var normal: Vector3D
        var binormal: Vector3D
    }

    private struct RotationValues: Sendable {
        var r00: Double
        var r01: Double
        var r02: Double
        var r10: Double
        var r11: Double
        var r12: Double
        var r20: Double
        var r21: Double
        var r22: Double
    }
}
