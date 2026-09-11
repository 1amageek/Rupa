import RealityKit
import RupaCore
import RupaViewportScene
import SwiftCAD
import SwiftUI

/// Mounts the native scene; the input surface and CAD mutation owners stay outside.
struct RealityViewportView: View {
    let viewport: RealityViewport
    let viewportRevision: UInt64
    let displayMode: ViewportDisplayMode
    let shading: ViewportShading
    let materialColors: [SceneOccurrenceID: ColorRGBA]
    let layout: ViewportLayout
    let interaction: MeshSourcePresentationInteractionStateResolver
    let sectionPlane: SectionAnalysisResult.Plane?
    let retainedSide: SectionAnalysisRetainedSide
    let sectionTolerance: Double
    var excludedRects: [CGRect] = []
    var gridRuler: RulerConfiguration? = nil
    var gridSpacing: ViewportGridVisualSpacingMode = .adaptive
    var onGridUpdateResult: ((MeshSourcePresentationRenderError?, ViewportProjectedGrid.ScaleReadout?) -> Void)? = nil
    let onUpdateResult: (MeshSourcePresentationRenderError?) -> Void
    @State private var mount = Mount()
    @Environment(\.displayScale) private var displayScale

    var body: some View {
        RealityView { content in
            content.camera = .virtual
            update(&content)
        } update: { content in
            update(&content)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onDisappear { mount.detach() }
    }

    private func update(_ content: inout RealityViewCameraContent) {
        let canUpdateSynchronously = mount.current?.matchesAppliedFrame(
            layout: layout, displayScale: displayScale, revision: viewportRevision,
            renderOrigin: viewport.renderOrigin
        ) == true
        if mount.current !== viewport {
            mount.detach()
            for entity in content.entities { content.remove(entity) }
            content.add(viewport.root)
            mount.current = viewport
        }
        viewport.bind(content, owner: ObjectIdentifier(mount))
        mount.cancelPending()
        viewport.root.isEnabled = true
        do {
            guard gridRuler == nil || onGridUpdateResult != nil else {
                throw MeshSourcePresentationRenderError(code: .failed, message: "Grid rendering requires a grid-status receiver.")
            }
            try viewport.applyCamera(layout: layout, displayScale: displayScale, revision: viewportRevision)
            try viewport.applyAppearance(displayMode: displayMode, shading: shading,
                                         materialColors: materialColors, interaction: interaction,
                                         sectionPlane: sectionPlane, retainedSide: retainedSide, sectionTolerance: sectionTolerance)
            mount.schedule(in: content, viewport: viewport,
                           safeRect: layout.fittingInsets.fittingRect(in: layout.viewportSize),
                           excludedRects: excludedRects, gridRuler: gridRuler, gridSpacing: gridSpacing,
                           callback: onUpdateResult, gridCallback: onGridUpdateResult)
            if canUpdateSynchronously {
                mount.updatePending()
            } else {
                viewport.setPresentationEnabled(false)
            }
        } catch {
            viewport.invalidateCamera()
            let failure = (error as? MeshSourcePresentationRenderError)
                ?? MeshSourcePresentationRenderError(code: .failed, message: error.localizedDescription)
            mount.report(failure, gridError: nil, gridReadout: nil,
                         callback: onUpdateResult, gridCallback: onGridUpdateResult)
        }
    }

    /// Reference storage prevents native updates from invalidating SwiftUI body.
    @MainActor
    private final class Mount {
        var current: RealityViewport?
        private var lastError: MeshSourcePresentationRenderError?
        private var lastGridError: MeshSourcePresentationRenderError?
        private var lastGridReadout: ViewportProjectedGrid.ScaleReadout?
        private var hasReported = false
        private var reportTask: Task<Void, Never>?
        private var frameSubscription: EventSubscription?
        private var pending: (() -> Bool)?

        func cancelPending() { pending = nil }

        func updatePending() {
            if let pending, pending() { self.pending = nil }
        }

        func schedule(in content: RealityViewCameraContent, viewport: RealityViewport,
                      safeRect: CGRect, excludedRects: [CGRect], gridRuler: RulerConfiguration?,
                      gridSpacing: ViewportGridVisualSpacingMode,
                      callback: @escaping (MeshSourcePresentationRenderError?) -> Void,
                      gridCallback: ((MeshSourcePresentationRenderError?, ViewportProjectedGrid.ScaleReadout?) -> Void)?) {
            pending = { [weak self] in
                guard let self, current === viewport,
                      viewport.isBound(to: ObjectIdentifier(self)) else { return true }
                do {
                    let error = try viewport.updateSpatialCamera(safeRect: safeRect, excludedRects: excludedRects,
                                                                gridRuler: gridRuler, gridSpacing: gridSpacing)
                    viewport.setPresentationEnabled(true)
                    report(nil, gridError: error, gridReadout: viewport.gridScaleReadout,
                           callback: callback, gridCallback: gridCallback)
                    return true
                } catch RealityViewportSpatialResources.CameraReadinessError.projectionUnavailable {
                    viewport.setPresentationEnabled(false)
                    report(.init(code: .failed, message: "Waiting for the mounted native camera projection."),
                           gridError: nil, gridReadout: nil, callback: callback, gridCallback: gridCallback)
                    return false
                } catch {
                    viewport.invalidateCamera()
                    let failure = (error as? MeshSourcePresentationRenderError)
                        ?? MeshSourcePresentationRenderError(code: .failed, message: error.localizedDescription)
                    report(failure, gridError: nil, gridReadout: nil, callback: callback, gridCallback: gridCallback)
                    return true
                }
            }
            if frameSubscription == nil {
                // RealityView state updates are not engine frames. Native project
                // becomes available after the scene has processed its camera.
                frameSubscription = content.subscribe(to: SceneEvents.Update.self) { [weak self] _ in
                    self?.updatePending()
                }
            }
        }

        func report(_ error: MeshSourcePresentationRenderError?, gridError: MeshSourcePresentationRenderError?,
                    gridReadout: ViewportProjectedGrid.ScaleReadout?,
                    callback: @escaping (MeshSourcePresentationRenderError?) -> Void,
                    gridCallback: ((MeshSourcePresentationRenderError?, ViewportProjectedGrid.ScaleReadout?) -> Void)?) {
            guard !hasReported || error != lastError || gridError != lastGridError || gridReadout != lastGridReadout else { return }
            hasReported = true
            lastError = error
            lastGridError = gridError
            lastGridReadout = gridReadout
            reportTask?.cancel()
            reportTask = Task { @MainActor [weak self] in
                guard !Task.isCancelled, let self,
                      current?.isBound(to: ObjectIdentifier(self)) == true else { return }
                callback(error)
                gridCallback?(gridError, gridReadout)
            }
        }

        func detach() {
            frameSubscription?.cancel()
            frameSubscription = nil
            pending = nil
            reportTask?.cancel()
            reportTask = nil
            current?.unbind(owner: ObjectIdentifier(self))
            current = nil
            hasReported = false
            lastError = nil
            lastGridError = nil
            lastGridReadout = nil
        }
    }
}
