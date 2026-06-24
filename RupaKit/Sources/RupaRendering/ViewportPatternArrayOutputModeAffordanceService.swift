import CoreGraphics
import RupaCore

struct ViewportPatternArrayOutputModeAffordanceService: Sendable {
    func candidates(
        document: DesignDocument,
        scene: ViewportScene,
        selection: SelectionModel,
        layout: ViewportLayout
    ) -> [ViewportPatternArrayOutputModeAffordanceCandidate] {
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
    ) -> ViewportPatternArrayOutputModeAffordanceCandidate? {
        guard let source = metadata.patternArrays[sourceID],
              let baseProjectedPoint = index.sourceBaseProjectedPoint(source: source, layout: layout) else {
            return nil
        }
        let center = CGPoint(
            x: baseProjectedPoint.x + 46.0,
            y: baseProjectedPoint.y - 34.0
        )
        let target = ViewportPatternArrayOutputModeHandleTarget(
            sourceID: sourceID,
            currentOutputMode: source.outputMode,
            nextOutputMode: Self.nextOutputMode(after: source.outputMode),
            center: center,
            hitRect: CGRect(
                x: center.x - 78.0,
                y: center.y - 13.0,
                width: 156.0,
                height: 26.0
            )
        )
        return ViewportPatternArrayOutputModeAffordanceCandidate(
            target: target,
            center: center,
            hitRect: target.hitRect
        )
    }

    private static func nextOutputMode(after outputMode: PatternArrayOutputMode) -> PatternArrayOutputMode {
        switch outputMode {
        case .componentInstance:
            .independentCopy
        case .independentCopy:
            .componentInstance
        }
    }
}

struct ViewportPatternArrayOutputModeAffordanceCandidate: Equatable {
    var target: ViewportPatternArrayOutputModeHandleTarget
    var center: CGPoint
    var hitRect: CGRect
}

struct ViewportPatternArrayOutputModeHandleTarget: Equatable {
    var sourceID: PatternArraySourceID
    var currentOutputMode: PatternArrayOutputMode
    var nextOutputMode: PatternArrayOutputMode
    var center: CGPoint
    var hitRect: CGRect

    var identity: ViewportPatternArrayOutputModeHandleIdentity {
        ViewportPatternArrayOutputModeHandleIdentity(sourceID: sourceID)
    }

    var title: String {
        switch currentOutputMode {
        case .componentInstance:
            "Output Instance"
        case .independentCopy:
            "Output Independent"
        }
    }

    var highlightedTitle: String {
        switch nextOutputMode {
        case .componentInstance:
            "Switch Instance"
        case .independentCopy:
            "Switch Independent"
        }
    }

    var commitTarget: ViewportPatternArrayOutputModeTarget {
        ViewportPatternArrayOutputModeTarget(
            sourceID: sourceID,
            outputMode: nextOutputMode
        )
    }
}

struct ViewportPatternArrayOutputModeHandleIdentity: Equatable {
    var sourceID: PatternArraySourceID
}
