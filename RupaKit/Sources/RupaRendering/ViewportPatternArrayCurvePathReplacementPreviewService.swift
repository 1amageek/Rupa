import CoreGraphics
import RupaCore

struct ViewportPatternArrayCurvePathReplacementPreviewService: Sendable {
    func preview(
        document: DesignDocument,
        scene: ViewportScene,
        layout: ViewportLayout,
        request: ViewportPatternArrayCurvePathReplacementPreviewRequest
    ) -> ViewportPatternArrayCurvePathReplacementPreview? {
        guard let source = document.productMetadata.patternArrays[request.sourceID],
              case .curve(var curve) = source.distribution,
              let basePoint = ViewportPatternArraySourceSelectionIndex(
                metadata: document.productMetadata,
                scene: scene,
                selection: .empty
              ).sourceBaseModelPoint(source: source) else {
            return nil
        }
        curve.path = request.path
        do {
            let distributionGeometry = try PatternArrayCurvePathGeometryService().distributionGeometry(
                for: curve,
                parameters: document.cadDocument.parameters,
                cadDocument: document.cadDocument
            )
            let transforms = try PatternArrayInstancePlanner().transforms(
                for: .curve(curve),
                parameters: document.cadDocument.parameters,
                cadDocument: document.cadDocument
            )
            let outputPoints = transforms.prefix(128).map { transform in
                layout.project(ViewportLayout.transformedPoint(basePoint, by: transform))
            }
            guard !outputPoints.isEmpty else {
                return nil
            }
            return ViewportPatternArrayCurvePathReplacementPreview(
                sourceID: request.sourceID,
                title: request.title,
                pathPoints: projectedPathPoints(
                    distributionGeometry.path,
                    layout: layout
                ),
                outputPoints: Array(outputPoints),
                totalOutputCount: transforms.count
            )
        } catch {
            return nil
        }
    }

    private func projectedPathPoints(
        _ geometry: PatternArrayCurvePathGeometry,
        layout: ViewportLayout
    ) -> [CGPoint] {
        let totalLength = geometry.totalLength
        guard totalLength.isFinite,
              totalLength > 1.0e-9 else {
            return []
        }
        let sampleCount = 72
        var points: [CGPoint] = []
        points.reserveCapacity(sampleCount + 1)
        for index in 0 ... sampleCount {
            do {
                let sample = try geometry.sample(
                    at: totalLength * Double(index) / Double(sampleCount)
                )
                points.append(layout.project(sample.point))
            } catch {
                return points
            }
        }
        return points
    }
}

struct ViewportPatternArrayCurvePathReplacementPreview: Equatable {
    var sourceID: PatternArraySourceID
    var title: String
    var pathPoints: [CGPoint]
    var outputPoints: [CGPoint]
    var totalOutputCount: Int
}
