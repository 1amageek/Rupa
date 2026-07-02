import RupaCore

@MainActor
struct PatternArrayEditingService {
    enum RectangularAxisSlot: Equatable, Sendable {
        case first
        case second
    }

    let session: EditorSession
    let sourceID: PatternArraySourceID
    private let anglePolicy = PatternArrayAnglePolicy.standard
    private let distancePolicy = PatternArrayDistancePolicy.standard
    private var defaultLinearAxisDistanceMeters: Double {
        WorkspaceEditingScaleDefaults(ruler: session.document.ruler).operationStepMeters
    }

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
        guard let source = session.document.productMetadata.patternArrays[sourceID],
              case .rectangular(var rectangular) = source.distribution else {
            return nil
        }
        let distanceQuantity = Quantity(
            value: distancePolicy.normalizedLinearDistanceMeters(meters),
            kind: .length
        )
        switch slot {
        case .first:
            if let result = expressionWritebackService.updateReferencedExpression(
                rectangular.firstAxis.distance,
                quantity: distanceQuantity
            ) {
                return commandResult(from: result)
            }
            rectangular.firstAxis.distance = .constant(distanceQuantity)
        case .second:
            guard var secondAxis = rectangular.secondAxis else {
                return nil
            }
            if let result = expressionWritebackService.updateReferencedExpression(
                secondAxis.distance,
                quantity: distanceQuantity
            ) {
                return commandResult(from: result)
            }
            secondAxis.distance = .constant(distanceQuantity)
            rectangular.secondAxis = secondAxis
        }
        return session.updatePatternArray(
            id: sourceID,
            distribution: .rectangular(rectangular)
        )
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
            let distanceMeters = distancePolicy.normalizedLinearDistanceMeters(fallbackDistanceMeters ?? 0.01)
            rectangular.secondAxis = PatternArrayLinearAxis(
                direction: defaultPerpendicularDirection(to: rectangular.firstAxis.direction),
                distance: .length(distanceMeters, .meter),
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
        guard let source = session.document.productMetadata.patternArrays[sourceID],
              case .radial(var radial) = source.distribution else {
            return nil
        }
        let angleRadians = PatternArrayEditingService.radians(fromDegrees: degrees)
        let angleQuantity = Quantity(
            value: anglePolicy.normalizedSignedAngleRadians(angleRadians),
            kind: .angle
        )
        if let result = expressionWritebackService.updateReferencedExpression(
            radial.angularAxis.angle,
            quantity: angleQuantity
        ) {
            return commandResult(from: result)
        }
        radial.angularAxis.angle = .constant(angleQuantity)
        return session.updatePatternArray(
            id: sourceID,
            distribution: .radial(radial)
        )
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
        guard let source = session.document.productMetadata.patternArrays[sourceID],
              case .radial(var radial) = source.distribution,
              var radialAxis = radial.radialAxis else {
            return nil
        }
        let distanceQuantity = Quantity(
            value: distancePolicy.normalizedLinearDistanceMeters(meters),
            kind: .length
        )
        if let result = expressionWritebackService.updateReferencedExpression(
            radialAxis.distance,
            quantity: distanceQuantity
        ) {
            return commandResult(from: result)
        }
        radialAxis.distance = .constant(distanceQuantity)
        radial.radialAxis = radialAxis
        return session.updatePatternArray(
            id: sourceID,
            distribution: .radial(radial)
        )
    }

    @discardableResult
    func setRadialAxisDistanceMode(_ distanceMode: PatternArrayDistanceMode) -> CommandExecutionResult? {
        updateRadialAxis { radialAxis in
            radialAxis.distanceMode = distanceMode
        }
    }

    @discardableResult
    func setRadialAxisEnabled(
        _ isEnabled: Bool,
        fallbackDistanceMeters: Double? = nil
    ) -> CommandExecutionResult? {
        guard let source = session.document.productMetadata.patternArrays[sourceID],
              case .radial(var radial) = source.distribution else {
            return nil
        }
        if isEnabled {
            guard radial.radialAxis == nil else {
                return nil
            }
            let distanceMeters = distancePolicy.normalizedLinearDistanceMeters(
                fallbackDistanceMeters ?? defaultLinearAxisDistanceMeters
            )
            radial.radialAxis = PatternArrayLinearAxis(
                direction: defaultPerpendicularDirection(to: radial.angularAxis.axis),
                distance: .length(distanceMeters, .meter),
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
    func setCurvePathPoint(
        index: Int,
        point: Point3D
    ) -> CommandExecutionResult? {
        guard let source = session.document.productMetadata.patternArrays[sourceID],
              case .curve(var curve) = source.distribution,
              case .polyline(var points, let normal) = curve.path,
              points.indices.contains(index) else {
            return nil
        }
        points[index] = point
        curve.path = .polyline(points: points, normal: normal)
        return session.updatePatternArray(
            id: sourceID,
            distribution: .curve(curve)
        )
    }

    @discardableResult
    func setCurveCopyCount(_ copyCount: Int) -> CommandExecutionResult? {
        updateCurve { curve in
            curve.copyCount = max(copyCount, 1)
        }
    }

    @discardableResult
    func setCurveTwist(degrees: Double) -> CommandExecutionResult? {
        let angleRadians = PatternArrayEditingService.radians(fromDegrees: degrees)
        return updateCurveExpression(
            keyPath: \.twist,
            quantity: Quantity(value: angleRadians, kind: .angle)
        )
    }

    @discardableResult
    func setCurveEndScale(_ scale: Double) -> CommandExecutionResult? {
        return updateCurveExpression(
            keyPath: \.endScale,
            quantity: Quantity(value: max(scale, 1.0e-9), kind: .scalar)
        )
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
            curve.extent = .length(
                distancePolicy.normalizedLinearDistanceMeters(fallbackDistanceMeters ?? 0.01),
                .meter
            )
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
        guard let source = session.document.productMetadata.patternArrays[sourceID],
              case .curve(var curve) = source.distribution else {
            return nil
        }
        let distanceQuantity = Quantity(
            value: distancePolicy.normalizedLinearDistanceMeters(meters),
            kind: .length
        )
        if curve.extentMode == .distance,
           let result = expressionWritebackService.updateReferencedExpression(
               curve.extent,
               quantity: distanceQuantity
           ) {
            return commandResult(from: result)
        }
        curve.extentMode = .distance
        curve.extent = .constant(distanceQuantity)
        return session.updatePatternArray(
            id: sourceID,
            distribution: .curve(curve)
        )
    }

    @discardableResult
    func setCurveExtentRatio(_ ratio: Double) -> CommandExecutionResult? {
        guard let source = session.document.productMetadata.patternArrays[sourceID],
              case .curve(var curve) = source.distribution else {
            return nil
        }
        let ratioQuantity = Quantity(
            value: clampedCurveExtentRatio(ratio),
            kind: .scalar
        )
        if curve.extentMode == .ratio,
           let result = expressionWritebackService.updateReferencedExpression(
               curve.extent,
               quantity: ratioQuantity
           ) {
            return commandResult(from: result)
        }
        curve.extentMode = .ratio
        curve.extent = .constant(ratioQuantity)
        return session.updatePatternArray(
            id: sourceID,
            distribution: .curve(curve)
        )
    }

    private var expressionWritebackService: PatternArrayExpressionWritebackService {
        PatternArrayExpressionWritebackService(session: session)
    }

    private func updateCurveExpression(
        keyPath: WritableKeyPath<CurvePatternArray, CADExpression>,
        quantity: Quantity
    ) -> CommandExecutionResult? {
        guard let source = session.document.productMetadata.patternArrays[sourceID],
              case .curve(var curve) = source.distribution else {
            return nil
        }
        if let result = expressionWritebackService.updateReferencedExpression(
            curve[keyPath: keyPath],
            quantity: quantity
        ) {
            return commandResult(from: result)
        }
        curve[keyPath: keyPath] = .constant(quantity)
        return session.updatePatternArray(
            id: sourceID,
            distribution: .curve(curve)
        )
    }

    private func commandResult(from writebackResult: PatternArrayExpressionWritebackResult) -> CommandExecutionResult? {
        switch writebackResult {
        case .updated(let commandResult):
            return commandResult
        case .blocked:
            return nil
        }
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

    private static func radians(fromDegrees degrees: Double) -> Double {
        degrees * .pi / 180.0
    }
}
