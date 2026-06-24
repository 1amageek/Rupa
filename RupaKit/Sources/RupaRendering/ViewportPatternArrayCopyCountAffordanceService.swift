import CoreGraphics
import RupaCore

struct ViewportPatternArrayCopyCountAffordanceService: Sendable {
    func candidates(
        document: DesignDocument,
        scene: ViewportScene,
        selection: SelectionModel,
        layout: ViewportLayout
    ) -> [ViewportPatternArrayCopyCountAffordanceCandidate] {
        let metadata = document.productMetadata
        let index = ViewportPatternArraySourceSelectionIndex(
            metadata: metadata,
            scene: scene,
            selection: selection
        )
        let sourceIDs = index.selectedSourceIDs()
        guard !sourceIDs.isEmpty else {
            return []
        }
        return sourceIDs.flatMap { sourceID in
            candidates(
                sourceID: sourceID,
                document: document,
                metadata: metadata,
                index: index,
                layout: layout
            )
        }
    }

    private func candidates(
        sourceID: PatternArraySourceID,
        document: DesignDocument,
        metadata: ProductMetadata,
        index: ViewportPatternArraySourceSelectionIndex,
        layout: ViewportLayout
    ) -> [ViewportPatternArrayCopyCountAffordanceCandidate] {
        guard let source = metadata.patternArrays[sourceID] else {
            return []
        }
        switch source.distribution {
        case .rectangular(let rectangular):
            return rectangularCandidates(
                sourceID: sourceID,
                rectangular: rectangular,
                source: source,
                index: index,
                layout: layout
            )
        case .radial(let radial):
            return radialCandidates(
                sourceID: sourceID,
                radial: radial,
                source: source,
                index: index,
                layout: layout
            )
        case .curve(let curve):
            if let candidate = curveCandidate(
                sourceID: sourceID,
                curve: curve,
                document: document,
                layout: layout
            ) {
                return [candidate]
            }
            return []
        }
    }

    private func rectangularCandidates(
        sourceID: PatternArraySourceID,
        rectangular: RectangularPatternArray,
        source: PatternArraySource,
        index: ViewportPatternArraySourceSelectionIndex,
        layout: ViewportLayout
    ) -> [ViewportPatternArrayCopyCountAffordanceCandidate] {
        guard let baseProjectedPoint = index.sourceBaseProjectedPoint(source: source, layout: layout) else {
            return []
        }
        var result: [ViewportPatternArrayCopyCountAffordanceCandidate] = []
        if let candidate = linearCandidate(
            sourceID: sourceID,
            slot: .rectangularFirst,
            axis: rectangular.firstAxis,
            baseProjectedPoint: baseProjectedPoint,
            layout: layout
        ) {
            result.append(candidate)
        }
        if let secondAxis = rectangular.secondAxis,
           let candidate = linearCandidate(
            sourceID: sourceID,
            slot: .rectangularSecond,
            axis: secondAxis,
            baseProjectedPoint: baseProjectedPoint,
            layout: layout
           ) {
            result.append(candidate)
        }
        return result
    }

    private func radialCandidates(
        sourceID: PatternArraySourceID,
        radial: RadialPatternArray,
        source: PatternArraySource,
        index: ViewportPatternArraySourceSelectionIndex,
        layout: ViewportLayout
    ) -> [ViewportPatternArrayCopyCountAffordanceCandidate] {
        var result: [ViewportPatternArrayCopyCountAffordanceCandidate] = []
        if let referencePoint = index.sourceBaseModelPoint(source: source),
           radial.angularAxis.angleMode == .spacing,
           let angleRadians = constantAngleRadians(radial.angularAxis.angle),
           let geometry = ViewportPatternArrayCopyCountAngularGeometry(
            center: radial.angularAxis.center,
            axis: radial.angularAxis.axis,
            referencePoint: referencePoint,
            stepAngleRadians: angleRadians,
            copyCount: radial.angularAxis.copyCount,
            layout: layout
           ) {
            let target = ViewportPatternArrayCopyCountHandleTarget(
                sourceID: sourceID,
                slot: .radialAngular,
                geometry: .angular(geometry)
            )
            result.append(ViewportPatternArrayCopyCountAffordanceCandidate(target: target, geometry: target.geometry))
        }
        if let radialAxis = radial.radialAxis,
           let baseProjectedPoint = index.sourceBaseProjectedPoint(source: source, layout: layout),
           let candidate = linearCandidate(
            sourceID: sourceID,
            slot: .radialAxis,
            axis: radialAxis,
            baseProjectedPoint: baseProjectedPoint,
            layout: layout
           ) {
            result.append(candidate)
        }
        return result
    }

    private func linearCandidate(
        sourceID: PatternArraySourceID,
        slot: ViewportPatternArrayCopyCountSlot,
        axis: PatternArrayLinearAxis,
        baseProjectedPoint: CGPoint,
        layout: ViewportLayout
    ) -> ViewportPatternArrayCopyCountAffordanceCandidate? {
        guard axis.distanceMode == .spacing,
              let distanceMeters = constantLengthMeters(axis.distance),
              let geometry = ViewportPatternArrayCopyCountLinearGeometry(
                baseProjectedPoint: baseProjectedPoint,
                axisDirection: axis.direction,
                distanceMeters: distanceMeters,
                copyCount: axis.copyCount,
                layout: layout
              ) else {
            return nil
        }
        let target = ViewportPatternArrayCopyCountHandleTarget(
            sourceID: sourceID,
            slot: slot,
            geometry: .linear(geometry)
        )
        return ViewportPatternArrayCopyCountAffordanceCandidate(target: target, geometry: target.geometry)
    }

    private func curveCandidate(
        sourceID: PatternArraySourceID,
        curve: CurvePatternArray,
        document: DesignDocument,
        layout: ViewportLayout
    ) -> ViewportPatternArrayCopyCountAffordanceCandidate? {
        do {
            let distributionGeometry = try PatternArrayCurvePathGeometryService().distributionGeometry(
                for: curve,
                parameters: document.cadDocument.parameters,
                cadDocument: document.cadDocument
            )
            guard let geometry = ViewportPatternArrayCopyCountCurveGeometry(
                path: distributionGeometry.path,
                distributionLength: distributionGeometry.distributionLength,
                copyCount: curve.copyCount,
                layout: layout
            ) else {
                return nil
            }
            let target = ViewportPatternArrayCopyCountHandleTarget(
                sourceID: sourceID,
                slot: .curve,
                geometry: .curve(geometry)
            )
            return ViewportPatternArrayCopyCountAffordanceCandidate(target: target, geometry: target.geometry)
        } catch {
            return nil
        }
    }

    private func constantLengthMeters(_ expression: CADExpression) -> Double? {
        guard case .constant(let quantity) = expression,
              quantity.kind == .length,
              quantity.value.isFinite,
              quantity.value > 0.0 else {
            return nil
        }
        return quantity.value
    }

    private func constantAngleRadians(_ expression: CADExpression) -> Double? {
        guard case .constant(let quantity) = expression,
              quantity.kind == .angle,
              quantity.value.isFinite else {
            return nil
        }
        return quantity.value
    }
}

struct ViewportPatternArrayCopyCountAffordanceCandidate: Equatable {
    var target: ViewportPatternArrayCopyCountHandleTarget
    var geometry: ViewportPatternArrayCopyCountAffordanceGeometry
}

struct ViewportPatternArrayCopyCountHandleTarget: Equatable {
    var sourceID: PatternArraySourceID
    var slot: ViewportPatternArrayCopyCountSlot
    var geometry: ViewportPatternArrayCopyCountAffordanceGeometry

    var identity: ViewportPatternArrayCopyCountHandleIdentity {
        ViewportPatternArrayCopyCountHandleIdentity(
            sourceID: sourceID,
            slot: slot
        )
    }

    var title: String {
        switch slot {
        case .rectangularFirst:
            "Axis 1 Count"
        case .rectangularSecond:
            "Axis 2 Count"
        case .radialAngular:
            "Radial Count"
        case .radialAxis:
            "Radius Count"
        case .curve:
            "Curve Count"
        }
    }
}

struct ViewportPatternArrayCopyCountHandleIdentity: Equatable {
    var sourceID: PatternArraySourceID
    var slot: ViewportPatternArrayCopyCountSlot
}
