import CoreGraphics
import RupaCore
import RupaRendering
import SwiftCAD

struct WorkspaceSavedViewBuilder: Sendable {
    func makeSavedView(
        name: String,
        workspaceState: WorkspaceState,
        projectionBasis: ViewportProjectionBasis,
        cameraFrame: ViewportCameraFrame? = nil
    ) -> SavedView {
        let ruler = workspaceState.ruler.normalizedForWorkspaceScale()
        let visibleHeightMeters = ViewportCameraFrame.normalizedVisibleHeightMeters(
            cameraFrame?.visibleHeightMeters ?? ruler.visibleSpanMeters
        )
        return SavedView(
            name: name,
            camera: SavedViewCamera(
                target: cameraFrame?.target ?? .origin,
                distanceMeters: visibleHeightMeters,
                yawRadians: Double(projectionBasis.orbitYawRadians),
                pitchRadians: Double(projectionBasis.orbitElevationRadians)
            ),
            projection: .orthographic(heightMeters: visibleHeightMeters),
            clipping: SavedViewClipping(),
            visibility: SavedViewVisibility(),
            sectionState: SavedViewSectionState(
                activeConstructionPlaneID: workspaceState.activeConstructionPlaneID
            ),
            displayScale: SavedViewDisplayScale(
                ruler: ruler,
                scaleBarLengthMeters: ruler.majorTickMeters
            )
        )
    }

    func projectionBasis(for savedView: SavedView) -> ViewportProjectionBasis {
        ViewportProjectionBasis.orbit(
            yaw: CGFloat(savedView.camera.yawRadians),
            elevation: CGFloat(savedView.camera.pitchRadians)
        )
    }

    func cameraFrameRequest(for savedView: SavedView) -> ViewportCameraFrameRequest {
        let basis = projectionBasis(for: savedView)
        let visibleHeightMeters = savedView.projection.orthographicHeightMeters
            ?? savedView.camera.distanceMeters
        return ViewportCameraFrameRequest(
            target: savedView.camera.target,
            visibleHeightMeters: visibleHeightMeters,
            basis: basis
        )
    }

    func sortedSavedViews(in document: DesignDocument) -> [SavedView] {
        document.productMetadata.savedViews.values.sorted { left, right in
            if left.name != right.name {
                return left.name.localizedStandardCompare(right.name) == .orderedAscending
            }
            return left.id.description < right.id.description
        }
    }

    func nextSavedViewName(in document: DesignDocument) -> String {
        let names = Set(document.productMetadata.savedViews.values.map(\.name))
        var index = names.count + 1
        while true {
            let candidate = "View \(index)"
            if !names.contains(candidate) {
                return candidate
            }
            index += 1
        }
    }

    func scaleTitle(for savedView: SavedView) -> String {
        if let preset = savedView.displayScale.matchedPreset {
            return "\(preset.compactWorkspaceTitle) · \(savedView.displayScale.displayUnit.symbol)"
        }
        return "Custom · \(savedView.displayScale.displayUnit.symbol)"
    }

    func projectionTitle(for savedView: SavedView) -> String {
        switch savedView.projection.mode {
        case .orthographic:
            return "Ortho"
        case .perspective:
            return "Persp"
        }
    }
}
