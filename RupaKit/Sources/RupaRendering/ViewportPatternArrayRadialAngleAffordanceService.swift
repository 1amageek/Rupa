import RupaCore

struct ViewportPatternArrayRadialAngleAffordanceService: Sendable {
    func candidates(
        document: DesignDocument,
        scene: ViewportScene,
        selection: SelectionModel,
        layout: ViewportLayout
    ) -> [ViewportPatternArrayRadialAngleAffordanceCandidate] {
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
        return sourceIDs.compactMap { sourceID in
            candidate(
                sourceID: sourceID,
                metadata: metadata,
                index: index,
                layout: layout
            )
        }
    }

    private func candidate(
        sourceID: PatternArraySourceID,
        metadata: ProductMetadata,
        index: ViewportPatternArraySourceSelectionIndex,
        layout: ViewportLayout
    ) -> ViewportPatternArrayRadialAngleAffordanceCandidate? {
        guard let source = metadata.patternArrays[sourceID],
              case .radial(let radial) = source.distribution,
              let angleRadians = constantAngleRadians(radial.angularAxis.angle),
              let referencePoint = index.sourceBaseModelPoint(source: source),
              let geometry = ViewportPatternArrayRadialAngleAffordanceGeometry(
                  center: radial.angularAxis.center,
                  axis: radial.angularAxis.axis,
                  referencePoint: referencePoint,
                  angleRadians: angleRadians,
                  layout: layout
              ) else {
            return nil
        }
        return ViewportPatternArrayRadialAngleAffordanceCandidate(
            target: ViewportPatternArrayRadialAngleHandleTarget(
                sourceID: sourceID,
                angleMode: radial.angularAxis.angleMode,
                geometry: geometry
            ),
            geometry: geometry
        )
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

struct ViewportPatternArrayRadialAngleAffordanceCandidate: Equatable {
    var target: ViewportPatternArrayRadialAngleHandleTarget
    var geometry: ViewportPatternArrayRadialAngleAffordanceGeometry
}

struct ViewportPatternArrayRadialAngleHandleTarget: Equatable {
    var sourceID: PatternArraySourceID
    var angleMode: PatternArrayAngleMode
    var geometry: ViewportPatternArrayRadialAngleAffordanceGeometry

    var identity: ViewportPatternArrayRadialAngleHandleIdentity {
        ViewportPatternArrayRadialAngleHandleIdentity(sourceID: sourceID)
    }

    var angleModeTitle: String {
        switch angleMode {
        case .spacing:
            "Spacing"
        case .extent:
            "Extent"
        }
    }
}

struct ViewportPatternArrayRadialAngleHandleIdentity: Equatable {
    var sourceID: PatternArraySourceID
}
