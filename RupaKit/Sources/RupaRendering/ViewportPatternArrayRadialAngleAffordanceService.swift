import RupaCore
import RupaViewportScene

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
        let expressionResolver = PatternArrayExpressionResolver(parameters: document.cadDocument.parameters)
        return sourceIDs.compactMap { sourceID in
            candidate(
                sourceID: sourceID,
                metadata: metadata,
                expressionResolver: expressionResolver,
                index: index,
                layout: layout
            )
        }
    }

    private func candidate(
        sourceID: PatternArraySourceID,
        metadata: ProductMetadata,
        expressionResolver: PatternArrayExpressionResolver,
        index: ViewportPatternArraySourceSelectionIndex,
        layout: ViewportLayout
    ) -> ViewportPatternArrayRadialAngleAffordanceCandidate? {
        guard let source = metadata.patternArrays[sourceID],
              case .radial(let radial) = source.distribution,
              let angleRadians = resolvedAngleRadians(
                  radial.angularAxis.angle,
                  expressionResolver: expressionResolver
              ),
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

    private func resolvedAngleRadians(
        _ expression: CADExpression,
        expressionResolver: PatternArrayExpressionResolver
    ) -> Double? {
        do {
            let value = try expressionResolver.angleRadians(for: expression)
            guard value.isFinite else {
                return nil
            }
            return value
        } catch {
            return nil
        }
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
