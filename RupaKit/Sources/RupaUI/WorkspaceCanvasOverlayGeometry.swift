import CoreGraphics
import RupaRendering

enum WorkspaceCanvasOverlayGeometry {
    static func normalizedHeight(_ height: CGFloat) -> CGFloat {
        max(0.0, height.rounded(.up))
    }

    static func normalizedExclusions(
        _ rectsByID: [WorkspaceCanvasOverlayChromeID: CGRect]
    ) -> [ViewportCanvasOverlayExclusion] {
        rectsByID.compactMap { id, rect in
            guard rect.isNull == false,
                  rect.isEmpty == false,
                  rect.origin.x.isFinite,
                  rect.origin.y.isFinite,
                  rect.width.isFinite,
                  rect.height.isFinite else {
                return nil
            }

            let minX = rect.minX.rounded(.down)
            let minY = rect.minY.rounded(.down)
            let maxX = rect.maxX.rounded(.up)
            let maxY = rect.maxY.rounded(.up)
            let normalized = CGRect(
                x: minX,
                y: minY,
                width: max(0.0, maxX - minX),
                height: max(0.0, maxY - minY)
            )
            guard normalized.isEmpty == false else {
                return nil
            }
            return ViewportCanvasOverlayExclusion(
                rect: normalized,
                fittingEdges: id.fittingEdges
            )
        }
        .sorted { left, right in
            if left.rect.minY != right.rect.minY {
                return left.rect.minY < right.rect.minY
            }
            if left.rect.minX != right.rect.minX {
                return left.rect.minX < right.rect.minX
            }
            if left.rect.width != right.rect.width {
                return left.rect.width < right.rect.width
            }
            return left.rect.height < right.rect.height
        }
    }
}
