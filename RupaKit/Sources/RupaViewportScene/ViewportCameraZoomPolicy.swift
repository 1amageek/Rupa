import CoreGraphics
import RupaCore

public enum ViewportCameraZoomPolicy {
    public static let targetMinorTickPixels: CGFloat = 20.0
    public static let absoluteMaximumZoom: CGFloat = 65_536.0

    public static func maximumZoom(
        for document: DesignDocument,
        identityScale: CGFloat
    ) -> CGFloat {
        let ruler = document.ruler.normalizedForWorkspaceScale()
        let referenceMeters = max(CGFloat(zoomReferenceMeters(for: ruler)), 1.0e-12)
        let scale = max(identityScale, 1.0e-12)
        let requiredZoom = targetMinorTickPixels / (referenceMeters * scale)
        guard requiredZoom.isFinite else {
            return ViewportCamera.maximumZoom
        }
        return min(
            max(ViewportCamera.maximumZoom, requiredZoom),
            absoluteMaximumZoom
        )
    }

    private static func zoomReferenceMeters(for ruler: RulerConfiguration) -> Double {
        let workspaceDetailMeters = max(ruler.visibleSpanMeters / 100_000.0, 1.0)
        return min(ruler.minorTickMeters, workspaceDetailMeters)
    }
}
