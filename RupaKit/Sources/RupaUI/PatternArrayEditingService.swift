import RupaCore

@MainActor
struct PatternArrayEditingService {
    typealias CurrentContextOperation = @MainActor @Sendable (PatternArrayEditingService) -> Void

    enum RectangularAxisSlot: Equatable, Sendable {
        case first
        case second
    }

    let document: DesignDocument
    let workspaceState: WorkspaceState
    let submit: (EditorCommand) -> Void
    let report: (String, EditorDiagnostic.Severity) -> Void
    let sourceID: PatternArraySourceID
    let submitCurrent: ((@escaping CurrentContextOperation) -> Void)?
    private let anglePolicy = PatternArrayAnglePolicy.standard
    private let distancePolicy = PatternArrayDistancePolicy.standard
    private var defaultLinearAxisDistanceMeters: Double {
        WorkspaceInteractionScaleDefaults(ruler: workspaceState.ruler).operationStepMeters
    }

    init(
        document: DesignDocument,
        workspaceState: WorkspaceState,
        submit: @escaping (EditorCommand) -> Void,
        report: @escaping (String, EditorDiagnostic.Severity) -> Void,
        sourceID: PatternArraySourceID,
        submitCurrent: ((@escaping CurrentContextOperation) -> Void)? = nil
    ) {
        self.document = document
        self.workspaceState = workspaceState
        self.submit = submit
        self.report = report
        self.sourceID = sourceID
        self.submitCurrent = submitCurrent
    }

    func setOutputMode(_ outputMode: PatternArrayOutputMode) {
        if submitCurrent != nil {
            submitCurrent? { $0.setOutputMode(outputMode) }
            return
        }
        updatePatternArray(id: sourceID, outputMode: outputMode)
    }

    func setRectangularAxisCopyCount(
        slot: RectangularAxisSlot,
        copyCount: Int
    ) {
        if submitCurrent != nil {
            submitCurrent? { $0.setRectangularAxisCopyCount(slot: slot, copyCount: copyCount) }
            return
        }
        updateRectangularAxis(slot: slot) { axis in
            axis.copyCount = max(copyCount, 1)
        }
    }

    func setRectangularAxisDistance(
        slot: RectangularAxisSlot,
        meters: Double
    ) {
        if submitCurrent != nil {
            submitCurrent? { $0.setRectangularAxisDistance(slot: slot, meters: meters) }
            return
        }
        guard let source = document.productMetadata.patternArrays[sourceID],
              case .rectangular(var rectangular) = source.distribution else {
            return
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
                handleWriteback(result)
                return
            }
            rectangular.firstAxis.distance = .constant(distanceQuantity)
        case .second:
            guard var secondAxis = rectangular.secondAxis else {
                return
            }
            if let result = expressionWritebackService.updateReferencedExpression(
                secondAxis.distance,
                quantity: distanceQuantity
            ) {
                handleWriteback(result)
                return
            }
            secondAxis.distance = .constant(distanceQuantity)
            rectangular.secondAxis = secondAxis
        }
        updatePatternArray(
            id: sourceID,
            distribution: .rectangular(rectangular)
        )
    }

    func setRectangularAxisDistanceMode(
        slot: RectangularAxisSlot,
        distanceMode: PatternArrayDistanceMode
    ) {
        if submitCurrent != nil {
            submitCurrent? {
                $0.setRectangularAxisDistanceMode(slot: slot, distanceMode: distanceMode)
            }
            return
        }
        updateRectangularAxis(slot: slot) { axis in
            axis.distanceMode = distanceMode
        }
    }

    func setRectangularSecondAxisEnabled(
        _ isEnabled: Bool,
        fallbackDistanceMeters: Double?
    ) {
        if submitCurrent != nil {
            submitCurrent? {
                $0.setRectangularSecondAxisEnabled(
                    isEnabled,
                    fallbackDistanceMeters: fallbackDistanceMeters
                )
            }
            return
        }
        guard let source = document.productMetadata.patternArrays[sourceID],
              case .rectangular(var rectangular) = source.distribution else {
            return
        }
        if isEnabled {
            if rectangular.secondAxis == nil {
                let distanceMeters = distancePolicy.normalizedLinearDistanceMeters(
                    fallbackDistanceMeters ?? defaultLinearAxisDistanceMeters
                )
                rectangular.secondAxis = PatternArrayLinearAxis(
                    direction: defaultPerpendicularDirection(to: rectangular.firstAxis.direction),
                    distance: .length(distanceMeters, .meter),
                    copyCount: 1,
                    distanceMode: rectangular.firstAxis.distanceMode
                )
            }
        } else {
            rectangular.secondAxis = nil
        }
        updatePatternArray(
            id: sourceID,
            distribution: .rectangular(rectangular)
        )
    }

    func setRadialCenter(
        x: Double? = nil,
        y: Double? = nil,
        z: Double? = nil
    ) {
        if submitCurrent != nil {
            submitCurrent? { $0.setRadialCenter(x: x, y: y, z: z) }
            return
        }
        updateRadialAngularAxis { angularAxis in
            angularAxis.center = Point3D(
                x: x ?? angularAxis.center.x,
                y: y ?? angularAxis.center.y,
                z: z ?? angularAxis.center.z
            )
        }
    }

    func setRadialAxisDirection(
        x: Double? = nil,
        y: Double? = nil,
        z: Double? = nil
    ) {
        if submitCurrent != nil {
            submitCurrent? { $0.setRadialAxisDirection(x: x, y: y, z: z) }
            return
        }
        updateRadialAngularAxis { angularAxis in
            angularAxis.axis = Vector3D(
                x: x ?? angularAxis.axis.x,
                y: y ?? angularAxis.axis.y,
                z: z ?? angularAxis.axis.z
            )
        }
    }

    func setRadialAngularCopyCount(_ copyCount: Int) {
        if submitCurrent != nil {
            submitCurrent? { $0.setRadialAngularCopyCount(copyCount) }
            return
        }
        updateRadialAngularAxis { angularAxis in
            angularAxis.copyCount = max(copyCount, 1)
        }
    }

    func setRadialAngle(degrees: Double) {
        if submitCurrent != nil {
            submitCurrent? { $0.setRadialAngle(degrees: degrees) }
            return
        }
        guard let source = document.productMetadata.patternArrays[sourceID],
              case .radial(var radial) = source.distribution else {
            return
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
            handleWriteback(result)
            return
        }
        radial.angularAxis.angle = .constant(angleQuantity)
        updatePatternArray(
            id: sourceID,
            distribution: .radial(radial)
        )
    }

    func setRadialAngleMode(_ angleMode: PatternArrayAngleMode) {
        if submitCurrent != nil {
            submitCurrent? { $0.setRadialAngleMode(angleMode) }
            return
        }
        updateRadialAngularAxis { angularAxis in
            angularAxis.angleMode = angleMode
        }
    }

    func setRadialAxisCopyCount(_ copyCount: Int) {
        if submitCurrent != nil {
            submitCurrent? { $0.setRadialAxisCopyCount(copyCount) }
            return
        }
        updateRadialAxis { radialAxis in
            radialAxis.copyCount = max(copyCount, 1)
        }
    }

    func setRadialAxisDistance(_ meters: Double) {
        if submitCurrent != nil {
            submitCurrent? { $0.setRadialAxisDistance(meters) }
            return
        }
        guard let source = document.productMetadata.patternArrays[sourceID],
              case .radial(var radial) = source.distribution,
              var radialAxis = radial.radialAxis else {
            return
        }
        let distanceQuantity = Quantity(
            value: distancePolicy.normalizedLinearDistanceMeters(meters),
            kind: .length
        )
        if let result = expressionWritebackService.updateReferencedExpression(
            radialAxis.distance,
            quantity: distanceQuantity
        ) {
            handleWriteback(result)
                return
        }
        radialAxis.distance = .constant(distanceQuantity)
        radial.radialAxis = radialAxis
        updatePatternArray(
            id: sourceID,
            distribution: .radial(radial)
        )
    }

    func setRadialAxisDistanceMode(_ distanceMode: PatternArrayDistanceMode) {
        if submitCurrent != nil {
            submitCurrent? { $0.setRadialAxisDistanceMode(distanceMode) }
            return
        }
        updateRadialAxis { radialAxis in
            radialAxis.distanceMode = distanceMode
        }
    }

    func setRadialAxisEnabled(
        _ isEnabled: Bool,
        fallbackDistanceMeters: Double? = nil
    ) {
        if submitCurrent != nil {
            submitCurrent? {
                $0.setRadialAxisEnabled(
                    isEnabled,
                    fallbackDistanceMeters: fallbackDistanceMeters
                )
            }
            return
        }
        guard let source = document.productMetadata.patternArrays[sourceID],
              case .radial(var radial) = source.distribution else {
            return
        }
        if isEnabled {
            if radial.radialAxis == nil {
                let distanceMeters = distancePolicy.normalizedLinearDistanceMeters(
                    fallbackDistanceMeters ?? defaultLinearAxisDistanceMeters
                )
                radial.radialAxis = PatternArrayLinearAxis(
                    direction: defaultPerpendicularDirection(to: radial.angularAxis.axis),
                    distance: .length(distanceMeters, .meter),
                    copyCount: 1,
                    distanceMode: .spacing
                )
            }
        } else {
            radial.radialAxis = nil
        }
        updatePatternArray(
            id: sourceID,
            distribution: .radial(radial)
        )
    }

    func setCurvePath(_ path: PatternArrayCurvePath) {
        if submitCurrent != nil {
            submitCurrent? { $0.setCurvePath(path) }
            return
        }
        updateCurve { curve in
            curve.path = path
        }
    }

    func setCurvePathPoint(
        index: Int,
        point: Point3D
    ) {
        if submitCurrent != nil {
            submitCurrent? { $0.setCurvePathPoint(index: index, point: point) }
            return
        }
        guard let source = document.productMetadata.patternArrays[sourceID],
              case .curve(var curve) = source.distribution,
              case .polyline(var points, let normal) = curve.path,
              points.indices.contains(index) else {
            return
        }
        points[index] = point
        curve.path = .polyline(points: points, normal: normal)
        updatePatternArray(
            id: sourceID,
            distribution: .curve(curve)
        )
    }

    func setCurveCopyCount(_ copyCount: Int) {
        if submitCurrent != nil {
            submitCurrent? { $0.setCurveCopyCount(copyCount) }
            return
        }
        updateCurve { curve in
            curve.copyCount = max(copyCount, 1)
        }
    }

    func setCurveTwist(degrees: Double) {
        if submitCurrent != nil {
            submitCurrent? { $0.setCurveTwist(degrees: degrees) }
            return
        }
        let angleRadians = PatternArrayEditingService.radians(fromDegrees: degrees)
        return updateCurveExpression(
            keyPath: \.twist,
            quantity: Quantity(value: angleRadians, kind: .angle)
        )
    }

    func setCurveEndScale(_ scale: Double) {
        if submitCurrent != nil {
            submitCurrent? { $0.setCurveEndScale(scale) }
            return
        }
        return updateCurveExpression(
            keyPath: \.endScale,
            quantity: Quantity(value: max(scale, 1.0e-9), kind: .scalar)
        )
    }

    func setCurveAlignment(_ alignment: PatternArrayCurveAlignment) {
        if submitCurrent != nil {
            submitCurrent? { $0.setCurveAlignment(alignment) }
            return
        }
        updateCurve { curve in
            curve.alignment = alignment
        }
    }

    func setCurveExtentMode(
        _ extentMode: PatternArrayCurveExtentMode,
        fallbackDistanceMeters: Double?,
        fallbackRatio: Double?
    ) {
        if submitCurrent != nil {
            submitCurrent? {
                $0.setCurveExtentMode(
                    extentMode,
                    fallbackDistanceMeters: fallbackDistanceMeters,
                    fallbackRatio: fallbackRatio
                )
            }
            return
        }
        guard let source = document.productMetadata.patternArrays[sourceID],
              case .curve(var curve) = source.distribution else {
            return
        }
        if curve.extentMode != extentMode {
            curve.extentMode = extentMode
            switch extentMode {
            case .distance:
                curve.extent = .length(
                    distancePolicy.normalizedLinearDistanceMeters(
                        fallbackDistanceMeters ?? defaultLinearAxisDistanceMeters
                    ),
                    .meter
                )
            case .ratio:
                curve.extent = .scalar(clampedCurveExtentRatio(fallbackRatio ?? 1.0))
            }
        }
        updatePatternArray(
            id: sourceID,
            distribution: .curve(curve)
        )
    }

    func setCurveExtentDistance(_ meters: Double) {
        if submitCurrent != nil {
            submitCurrent? { $0.setCurveExtentDistance(meters) }
            return
        }
        guard let source = document.productMetadata.patternArrays[sourceID],
              case .curve(var curve) = source.distribution else {
            return
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
            handleWriteback(result)
                return
        }
        curve.extentMode = .distance
        curve.extent = .constant(distanceQuantity)
        updatePatternArray(
            id: sourceID,
            distribution: .curve(curve)
        )
    }

    func setCurveExtentRatio(_ ratio: Double) {
        if submitCurrent != nil {
            submitCurrent? { $0.setCurveExtentRatio(ratio) }
            return
        }
        guard let source = document.productMetadata.patternArrays[sourceID],
              case .curve(var curve) = source.distribution else {
            return
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
            handleWriteback(result)
                return
        }
        curve.extentMode = .ratio
        curve.extent = .constant(ratioQuantity)
        updatePatternArray(
            id: sourceID,
            distribution: .curve(curve)
        )
    }

    private var expressionWritebackService: PatternArrayExpressionWritebackService {
        PatternArrayExpressionWritebackService(
            document: document,
            submit: submit,
            report: report
        )
    }

    private func updateCurveExpression(
        keyPath: WritableKeyPath<CurvePatternArray, CADExpression>,
        quantity: Quantity
    ) {
        guard let source = document.productMetadata.patternArrays[sourceID],
              case .curve(var curve) = source.distribution else {
            return
        }
        if let result = expressionWritebackService.updateReferencedExpression(
            curve[keyPath: keyPath],
            quantity: quantity
        ) {
            handleWriteback(result)
                return
        }
        curve[keyPath: keyPath] = .constant(quantity)
        updatePatternArray(
            id: sourceID,
            distribution: .curve(curve)
        )
    }

    private func handleWriteback(_ writebackResult: PatternArrayExpressionWritebackResult) {
        switch writebackResult {
        case .updated, .blocked:
            return
        }
    }

    private func updatePatternArray(
        id: PatternArraySourceID,
        distribution: PatternArrayDistribution? = nil,
        outputMode: PatternArrayOutputMode? = nil
    ) {
        submit(
            .updatePatternArray(
                id: id,
                name: nil,
                definitionID: nil,
                distribution: distribution,
                outputMode: outputMode
            )
        )
    }

    private func updateCurve(
        update: (inout CurvePatternArray) -> Void
    ) {
        guard let source = document.productMetadata.patternArrays[sourceID],
              case .curve(var curve) = source.distribution else {
            return
        }
        update(&curve)
        updatePatternArray(
            id: sourceID,
            distribution: .curve(curve)
        )
    }

    private func updateRectangularAxis(
        slot: RectangularAxisSlot,
        update: (inout PatternArrayLinearAxis) -> Void
    ) {
        guard let source = document.productMetadata.patternArrays[sourceID],
              case .rectangular(var rectangular) = source.distribution else {
            return
        }
        switch slot {
        case .first:
            update(&rectangular.firstAxis)
        case .second:
            guard var secondAxis = rectangular.secondAxis else {
                return
            }
            update(&secondAxis)
            rectangular.secondAxis = secondAxis
        }
        updatePatternArray(
            id: sourceID,
            distribution: .rectangular(rectangular)
        )
    }

    private func updateRadialAngularAxis(
        update: (inout PatternArrayAngularAxis) -> Void
    ) {
        guard let source = document.productMetadata.patternArrays[sourceID],
              case .radial(var radial) = source.distribution else {
            return
        }
        update(&radial.angularAxis)
        updatePatternArray(
            id: sourceID,
            distribution: .radial(radial)
        )
    }

    private func updateRadialAxis(
        update: (inout PatternArrayLinearAxis) -> Void
    ) {
        guard let source = document.productMetadata.patternArrays[sourceID],
              case .radial(var radial) = source.distribution,
              var radialAxis = radial.radialAxis else {
            return
        }
        update(&radialAxis)
        radial.radialAxis = radialAxis
        updatePatternArray(
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
