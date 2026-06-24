import RupaCore

@MainActor
struct PatternArrayEditingService {
    enum RectangularAxisSlot: Equatable, Sendable {
        case first
        case second
    }

    let session: EditorSession
    let sourceID: PatternArraySourceID

    @discardableResult
    func setOutputMode(_ outputMode: PatternArrayOutputMode) -> CommandExecutionResult? {
        session.updatePatternArray(id: sourceID, outputMode: outputMode)
    }

    @discardableResult
    func setRectangularAxisCopyCount(
        slot: RectangularAxisSlot,
        copyCount: Int
    ) -> CommandExecutionResult? {
        updateRectangularAxis(slot: slot) { axis in
            axis.copyCount = max(copyCount, 1)
        }
    }

    @discardableResult
    func setRectangularAxisDistance(
        slot: RectangularAxisSlot,
        meters: Double
    ) -> CommandExecutionResult? {
        updateRectangularAxis(slot: slot) { axis in
            axis.distance = .length(max(meters, 0.0), .meter)
        }
    }

    @discardableResult
    func setRectangularAxisDistanceMode(
        slot: RectangularAxisSlot,
        distanceMode: PatternArrayDistanceMode
    ) -> CommandExecutionResult? {
        updateRectangularAxis(slot: slot) { axis in
            axis.distanceMode = distanceMode
        }
    }

    @discardableResult
    func setRectangularSecondAxisEnabled(
        _ isEnabled: Bool,
        fallbackDistanceMeters: Double?
    ) -> CommandExecutionResult? {
        guard let source = session.document.productMetadata.patternArrays[sourceID],
              case .rectangular(var rectangular) = source.distribution else {
            return nil
        }
        if isEnabled {
            guard rectangular.secondAxis == nil else {
                return nil
            }
            let distanceMeters = fallbackDistanceMeters ?? 0.01
            rectangular.secondAxis = PatternArrayLinearAxis(
                direction: defaultPerpendicularDirection(to: rectangular.firstAxis.direction),
                distance: .length(max(distanceMeters, 1.0e-9), .meter),
                copyCount: 1,
                distanceMode: rectangular.firstAxis.distanceMode
            )
        } else {
            guard rectangular.secondAxis != nil else {
                return nil
            }
            rectangular.secondAxis = nil
        }
        return session.updatePatternArray(
            id: sourceID,
            distribution: .rectangular(rectangular)
        )
    }

    @discardableResult
    func setRadialCenter(
        x: Double? = nil,
        y: Double? = nil,
        z: Double? = nil
    ) -> CommandExecutionResult? {
        updateRadialAngularAxis { angularAxis in
            angularAxis.center = Point3D(
                x: x ?? angularAxis.center.x,
                y: y ?? angularAxis.center.y,
                z: z ?? angularAxis.center.z
            )
        }
    }

    @discardableResult
    func setRadialAxisDirection(
        x: Double? = nil,
        y: Double? = nil,
        z: Double? = nil
    ) -> CommandExecutionResult? {
        updateRadialAngularAxis { angularAxis in
            angularAxis.axis = Vector3D(
                x: x ?? angularAxis.axis.x,
                y: y ?? angularAxis.axis.y,
                z: z ?? angularAxis.axis.z
            )
        }
    }

    @discardableResult
    func setRadialAngularCopyCount(_ copyCount: Int) -> CommandExecutionResult? {
        updateRadialAngularAxis { angularAxis in
            angularAxis.copyCount = max(copyCount, 1)
        }
    }

    @discardableResult
    func setRadialAngle(degrees: Double) -> CommandExecutionResult? {
        updateRadialAngularAxis { angularAxis in
            angularAxis.angle = .angle(degrees, .degree)
        }
    }

    @discardableResult
    func setRadialAngleMode(_ angleMode: PatternArrayAngleMode) -> CommandExecutionResult? {
        updateRadialAngularAxis { angularAxis in
            angularAxis.angleMode = angleMode
        }
    }

    @discardableResult
    func setRadialAxisCopyCount(_ copyCount: Int) -> CommandExecutionResult? {
        updateRadialAxis { radialAxis in
            radialAxis.copyCount = max(copyCount, 1)
        }
    }

    @discardableResult
    func setRadialAxisDistance(_ meters: Double) -> CommandExecutionResult? {
        updateRadialAxis { radialAxis in
            radialAxis.distance = .length(max(meters, 0.0), .meter)
        }
    }

    @discardableResult
    func setRadialAxisDistanceMode(_ distanceMode: PatternArrayDistanceMode) -> CommandExecutionResult? {
        updateRadialAxis { radialAxis in
            radialAxis.distanceMode = distanceMode
        }
    }

    @discardableResult
    func setRadialAxisEnabled(_ isEnabled: Bool) -> CommandExecutionResult? {
        guard let source = session.document.productMetadata.patternArrays[sourceID],
              case .radial(var radial) = source.distribution else {
            return nil
        }
        if isEnabled {
            guard radial.radialAxis == nil else {
                return nil
            }
            radial.radialAxis = PatternArrayLinearAxis(
                direction: defaultPerpendicularDirection(to: radial.angularAxis.axis),
                distance: .length(0.01, .meter),
                copyCount: 1,
                distanceMode: .spacing
            )
        } else {
            guard radial.radialAxis != nil else {
                return nil
            }
            radial.radialAxis = nil
        }
        return session.updatePatternArray(
            id: sourceID,
            distribution: .radial(radial)
        )
    }

    @discardableResult
    func setCurvePath(_ path: PatternArrayCurvePath) -> CommandExecutionResult? {
        updateCurve { curve in
            curve.path = path
        }
    }

    @discardableResult
    func setCurveCopyCount(_ copyCount: Int) -> CommandExecutionResult? {
        updateCurve { curve in
            curve.copyCount = max(copyCount, 1)
        }
    }

    @discardableResult
    func setCurveTwist(degrees: Double) -> CommandExecutionResult? {
        updateCurve { curve in
            curve.twist = .angle(degrees, .degree)
        }
    }

    @discardableResult
    func setCurveEndScale(_ scale: Double) -> CommandExecutionResult? {
        updateCurve { curve in
            curve.endScale = .scalar(max(scale, 1.0e-9))
        }
    }

    @discardableResult
    func setCurveAlignment(_ alignment: PatternArrayCurveAlignment) -> CommandExecutionResult? {
        updateCurve { curve in
            curve.alignment = alignment
        }
    }

    @discardableResult
    func setCurveExtentMode(
        _ extentMode: PatternArrayCurveExtentMode,
        fallbackDistanceMeters: Double?,
        fallbackRatio: Double?
    ) -> CommandExecutionResult? {
        guard let source = session.document.productMetadata.patternArrays[sourceID],
              case .curve(var curve) = source.distribution,
              curve.extentMode != extentMode else {
            return nil
        }
        curve.extentMode = extentMode
        switch extentMode {
        case .distance:
            curve.extent = .length(max(fallbackDistanceMeters ?? 0.01, 1.0e-9), .meter)
        case .ratio:
            curve.extent = .scalar(clampedCurveExtentRatio(fallbackRatio ?? 1.0))
        }
        return session.updatePatternArray(
            id: sourceID,
            distribution: .curve(curve)
        )
    }

    @discardableResult
    func setCurveExtentDistance(_ meters: Double) -> CommandExecutionResult? {
        updateCurve { curve in
            curve.extentMode = .distance
            curve.extent = .length(max(meters, 1.0e-9), .meter)
        }
    }

    @discardableResult
    func setCurveExtentRatio(_ ratio: Double) -> CommandExecutionResult? {
        updateCurve { curve in
            curve.extentMode = .ratio
            curve.extent = .scalar(clampedCurveExtentRatio(ratio))
        }
    }

    private func updateRectangularAxis(
        slot: RectangularAxisSlot,
        update: (inout PatternArrayLinearAxis) -> Void
    ) -> CommandExecutionResult? {
        guard let source = session.document.productMetadata.patternArrays[sourceID],
              case .rectangular(var rectangular) = source.distribution else {
            return nil
        }
        switch slot {
        case .first:
            update(&rectangular.firstAxis)
        case .second:
            guard var secondAxis = rectangular.secondAxis else {
                return nil
            }
            update(&secondAxis)
            rectangular.secondAxis = secondAxis
        }
        return session.updatePatternArray(
            id: sourceID,
            distribution: .rectangular(rectangular)
        )
    }

    private func updateRadialAngularAxis(
        update: (inout PatternArrayAngularAxis) -> Void
    ) -> CommandExecutionResult? {
        guard let source = session.document.productMetadata.patternArrays[sourceID],
              case .radial(var radial) = source.distribution else {
            return nil
        }
        update(&radial.angularAxis)
        return session.updatePatternArray(
            id: sourceID,
            distribution: .radial(radial)
        )
    }

    private func updateRadialAxis(
        update: (inout PatternArrayLinearAxis) -> Void
    ) -> CommandExecutionResult? {
        guard let source = session.document.productMetadata.patternArrays[sourceID],
              case .radial(var radial) = source.distribution,
              var radialAxis = radial.radialAxis else {
            return nil
        }
        update(&radialAxis)
        radial.radialAxis = radialAxis
        return session.updatePatternArray(
            id: sourceID,
            distribution: .radial(radial)
        )
    }

    private func updateCurve(
        update: (inout CurvePatternArray) -> Void
    ) -> CommandExecutionResult? {
        guard let source = session.document.productMetadata.patternArrays[sourceID],
              case .curve(var curve) = source.distribution else {
            return nil
        }
        update(&curve)
        return session.updatePatternArray(
            id: sourceID,
            distribution: .curve(curve)
        )
    }

    private func defaultPerpendicularDirection(to direction: Vector3D) -> Vector3D {
        let length = direction.length
        guard length.isFinite, length > 1.0e-9 else {
            return .unitY
        }
        let unitDirection = Vector3D(
            x: direction.x / length,
            y: direction.y / length,
            z: direction.z / length
        )
        return abs(unitDirection.dot(.unitY)) < 0.9 ? .unitY : .unitX
    }

    private func clampedCurveExtentRatio(_ ratio: Double) -> Double {
        guard ratio.isFinite else {
            return 1.0
        }
        return min(max(ratio, 1.0e-9), 1.0)
    }
}
