import RupaCore
import RupaViewportScene

struct ViewportPatternArrayCurveExtentAffordanceService: Sendable {
    func candidates(
        document: DesignDocument,
        scene: ViewportScene,
        selection: SelectionModel,
        layout: ViewportLayout
    ) -> [ViewportPatternArrayCurveExtentAffordanceCandidate] {
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
                document: document,
                metadata: metadata,
                layout: layout
            )
        }
    }

    private func candidate(
        sourceID: PatternArraySourceID,
        document: DesignDocument,
        metadata: ProductMetadata,
        layout: ViewportLayout
    ) -> ViewportPatternArrayCurveExtentAffordanceCandidate? {
        guard let source = metadata.patternArrays[sourceID],
              case .curve(let curve) = source.distribution else {
            return nil
        }
        do {
            let distributionGeometry = try PatternArrayCurvePathGeometryService().distributionGeometry(
                for: curve,
                parameters: document.cadDocument.parameters,
                cadDocument: document.cadDocument
            )
            guard let geometry = ViewportPatternArrayCurveExtentAffordanceGeometry(
                path: distributionGeometry.path,
                distributionLength: distributionGeometry.distributionLength,
                layout: layout
            ) else {
                return nil
            }
            return ViewportPatternArrayCurveExtentAffordanceCandidate(
                target: ViewportPatternArrayCurveExtentHandleTarget(
                    sourceID: sourceID,
                    extentMode: curve.extentMode,
                    geometry: geometry
                ),
                geometry: geometry
            )
        } catch {
            return nil
        }
    }
}

struct ViewportPatternArrayCurveExtentAffordanceCandidate: Equatable {
    var target: ViewportPatternArrayCurveExtentHandleTarget
    var geometry: ViewportPatternArrayCurveExtentAffordanceGeometry
}

struct ViewportPatternArrayCurveExtentHandleTarget: Equatable {
    var sourceID: PatternArraySourceID
    var extentMode: PatternArrayCurveExtentMode
    var geometry: ViewportPatternArrayCurveExtentAffordanceGeometry

    var identity: ViewportPatternArrayCurveExtentHandleIdentity {
        ViewportPatternArrayCurveExtentHandleIdentity(sourceID: sourceID)
    }

    var title: String {
        switch extentMode {
        case .distance:
            "Curve Extent"
        case .ratio:
            "Curve Ratio"
        }
    }
}

struct ViewportPatternArrayCurveExtentHandleIdentity: Equatable {
    var sourceID: PatternArraySourceID
}
