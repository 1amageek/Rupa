import CoreGraphics
import RupaCore
import RupaViewportScene

struct ViewportPatternArrayCurvePathPointAffordanceService: Sendable {
    func candidates(
        document: DesignDocument,
        scene: ViewportScene,
        selection: SelectionModel,
        layout: ViewportLayout
    ) -> [ViewportPatternArrayCurvePathPointAffordanceCandidate] {
        let metadata = document.productMetadata
        let index = ViewportPatternArraySourceSelectionIndex(
            metadata: metadata,
            scene: scene,
            selection: selection
        )
        return index.selectedSourceIDs().flatMap { sourceID in
            candidates(
                sourceID: sourceID,
                metadata: metadata,
                layout: layout
            )
        }
    }

    private func candidates(
        sourceID: PatternArraySourceID,
        metadata: ProductMetadata,
        layout: ViewportLayout
    ) -> [ViewportPatternArrayCurvePathPointAffordanceCandidate] {
        guard let source = metadata.patternArrays[sourceID],
              case .curve(let curve) = source.distribution,
              case .polyline(let points, _) = curve.path,
              points.count >= 2 else {
            return []
        }
        let projectedPathPoints = points.map(layout.project)
        return points.enumerated().map { index, point in
            let target = ViewportPatternArrayCurvePathPointHandleTarget(
                sourceID: sourceID,
                pointIndex: index,
                basePoint: point,
                pathPoints: points,
                projectedPoint: projectedPathPoints[index]
            )
            return ViewportPatternArrayCurvePathPointAffordanceCandidate(
                target: target,
                projectedPoint: projectedPathPoints[index],
                projectedPathPoints: projectedPathPoints
            )
        }
    }
}

struct ViewportPatternArrayCurvePathPointAffordanceCandidate: Equatable {
    var target: ViewportPatternArrayCurvePathPointHandleTarget
    var projectedPoint: CGPoint
    var projectedPathPoints: [CGPoint]
}

struct ViewportPatternArrayCurvePathPointHandleTarget: Equatable {
    var sourceID: PatternArraySourceID
    var pointIndex: Int
    var basePoint: Point3D
    var pathPoints: [Point3D]
    var projectedPoint: CGPoint

    var identity: ViewportPatternArrayCurvePathPointHandleIdentity {
        ViewportPatternArrayCurvePathPointHandleIdentity(
            sourceID: sourceID,
            pointIndex: pointIndex
        )
    }

    var title: String {
        "Path P\(pointIndex + 1)"
    }
}

struct ViewportPatternArrayCurvePathPointHandleIdentity: Equatable {
    var sourceID: PatternArraySourceID
    var pointIndex: Int
}
