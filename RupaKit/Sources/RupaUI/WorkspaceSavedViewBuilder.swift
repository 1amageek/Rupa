import CoreGraphics
import Foundation
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
        let projection: SavedViewProjection
        let distanceMeters: Double
        switch cameraFrame?.camera.projection ?? .parallel {
        case .parallel:
            projection = .orthographic(heightMeters: visibleHeightMeters)
            distanceMeters = visibleHeightMeters
        case .perspective(let fieldOfViewRadians):
            projection = .perspective(fieldOfViewRadians: fieldOfViewRadians)
            distanceMeters = visibleHeightMeters / (2 * tan(fieldOfViewRadians / 2))
        }
        return SavedView(
            name: name,
            camera: SavedViewCamera(
                target: cameraFrame?.target ?? .origin,
                distanceMeters: distanceMeters,
                yawRadians: Double(projectionBasis.orbitYawRadians),
                pitchRadians: Double(projectionBasis.orbitElevationRadians)
            ),
            projection: projection,
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

    func cameraFrameRequest(for savedView: SavedView) throws -> ViewportCameraFrameRequest {
        try savedView.camera.validate()
        try savedView.projection.validate()
        let basis = projectionBasis(for: savedView)
        let visibleHeightMeters: Double
        let projection: ViewportCameraProjection
        switch (savedView.projection.mode, savedView.projection.orthographicHeightMeters,
                savedView.projection.fieldOfViewRadians) {
        case (.orthographic, let height?, nil):
            visibleHeightMeters = height
            projection = .parallel
        case (.perspective, nil, let fieldOfViewRadians?):
            visibleHeightMeters = 2 * savedView.camera.distanceMeters * tan(fieldOfViewRadians / 2)
            projection = .perspective(fieldOfViewRadians: fieldOfViewRadians)
        default:
            throw DocumentValidationError.invalidProductMetadata("Saved view projection is invalid.")
        }
        guard visibleHeightMeters.isFinite, visibleHeightMeters > 0 else {
            throw DocumentValidationError.invalidProductMetadata("Saved view visible height is out of range.")
        }
        return ViewportCameraFrameRequest(
            target: savedView.camera.target,
            visibleHeightMeters: visibleHeightMeters,
            basis: basis,
            projection: projection
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
