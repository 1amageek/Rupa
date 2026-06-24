import CoreGraphics
import RupaCore

struct ViewportPatternArrayLinearAxisAffordanceService: Sendable {
    func candidates(
        document: DesignDocument,
        scene: ViewportScene,
        selection: SelectionModel,
        layout: ViewportLayout
    ) -> [ViewportPatternArrayLinearAxisAffordanceCandidate] {
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
                metadata: metadata,
                index: index,
                layout: layout
            )
        }
    }

    private func candidates(
        sourceID: PatternArraySourceID,
        metadata: ProductMetadata,
        index: ViewportPatternArraySourceSelectionIndex,
        layout: ViewportLayout
    ) -> [ViewportPatternArrayLinearAxisAffordanceCandidate] {
        guard let source = metadata.patternArrays[sourceID],
              let baseProjectedPoint = index.sourceBaseProjectedPoint(source: source, layout: layout) else {
            return []
        }

        var result: [ViewportPatternArrayLinearAxisAffordanceCandidate] = []
        switch source.distribution {
        case .rectangular(let rectangular):
            if let candidate = candidate(
                sourceID: sourceID,
                axisSlot: .first,
                axis: rectangular.firstAxis,
                baseProjectedPoint: baseProjectedPoint,
                layout: layout
            ) {
                result.append(candidate)
            }
            if let secondAxis = rectangular.secondAxis,
               let candidate = candidate(
                   sourceID: sourceID,
                   axisSlot: .second,
                   axis: secondAxis,
                   baseProjectedPoint: baseProjectedPoint,
                   layout: layout
               ) {
                result.append(candidate)
            }
        case .radial(let radial):
            if let radialAxis = radial.radialAxis,
               let candidate = candidate(
                   sourceID: sourceID,
                   axisSlot: .radial,
                   axis: radialAxis,
                   baseProjectedPoint: baseProjectedPoint,
                   layout: layout
               ) {
                result.append(candidate)
            }
        case .curve:
            break
        }
        return result
    }

    private func candidate(
        sourceID: PatternArraySourceID,
        axisSlot: ViewportPatternArrayLinearAxisSlot,
        axis: PatternArrayLinearAxis,
        baseProjectedPoint: CGPoint,
        layout: ViewportLayout
    ) -> ViewportPatternArrayLinearAxisAffordanceCandidate? {
        guard let distanceMeters = constantLengthMeters(axis.distance),
              let geometry = ViewportPatternArrayLinearAxisAffordanceGeometry(
                  baseProjectedPoint: baseProjectedPoint,
                  axisDirection: axis.direction,
                  distanceMeters: distanceMeters,
                  layout: layout
              ) else {
            return nil
        }
        return ViewportPatternArrayLinearAxisAffordanceCandidate(
            target: ViewportPatternArrayLinearAxisHandleTarget(
                sourceID: sourceID,
                axisSlot: axisSlot,
                distanceMode: axis.distanceMode,
                geometry: geometry
            ),
            geometry: geometry
        )
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
}

struct ViewportPatternArrayLinearAxisAffordanceCandidate: Equatable {
    var target: ViewportPatternArrayLinearAxisHandleTarget
    var geometry: ViewportPatternArrayLinearAxisAffordanceGeometry
}

struct ViewportPatternArrayLinearAxisHandleTarget: Equatable {
    var sourceID: PatternArraySourceID
    var axisSlot: ViewportPatternArrayLinearAxisSlot
    var distanceMode: PatternArrayDistanceMode
    var geometry: ViewportPatternArrayLinearAxisAffordanceGeometry

    var identity: ViewportPatternArrayLinearAxisHandleIdentity {
        ViewportPatternArrayLinearAxisHandleIdentity(
            sourceID: sourceID,
            axisSlot: axisSlot
        )
    }

    var distanceModeTitle: String {
        switch distanceMode {
        case .spacing:
            "Spacing"
        case .extent:
            "Extent"
        }
    }
}

struct ViewportPatternArrayLinearAxisHandleIdentity: Equatable {
    var sourceID: PatternArraySourceID
    var axisSlot: ViewportPatternArrayLinearAxisSlot
}
