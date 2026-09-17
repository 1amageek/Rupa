import RealityKit
import RupaCore
import RupaViewportScene
import SwiftCAD
import SwiftUI

/// Mounts the native scene; the input surface and CAD mutation owners stay outside.
///
/// One canvas owns one native scene for its lifetime. An absent frame leaves
/// the root this host last attached in that scene, so a rebuild never blacks
/// the canvas out; its successor is what removes it. The host is never
/// unmounted, because a rebuilt frame reuses native resources and a resource
/// shared by two scenes migrates its asset root between them.
struct RealityViewportView: View {
    let viewport: RealityViewport?
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
    /// Receives the bounds ruler axes this mount's frame refused to place, or
    /// their absence while no mounted frame has placed them.
    var onBoundsRulerUpdateResult: ((Set<ViewportMeasurementRulerAxis>?) -> Void)? = nil
    /// Receives the camera revision this mount last installed, or its absence.
    ///
    /// Overlays whose screen position belongs to the frame need it because a
    /// SwiftUI body runs before `applyCamera` and the surface is not
    /// observable, so nothing else republishes the applied frame on an orbit.
    var onAppliedFrameRevision: ((UInt64?) -> Void)? = nil
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
        // A withdrawn frame keeps drawing. The root this host last attached
        // stays in the scene until its successor replaces it, so a rebuild
        // never empties the scene and blacks the canvas out. The parent cache
        // has already withdrawn authority, so whatever this frame still
        // reports reaches no state.
        guard let viewport else { return }
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
                           callback: onUpdateResult, gridCallback: onGridUpdateResult,
                           boundsRulerCallback: onBoundsRulerUpdateResult,
                           revisionCallback: onAppliedFrameRevision)
            if canUpdateSynchronously {
                mount.updatePending()
            } else {
                viewport.setPresentationEnabled(false)
            }
        } catch {
            viewport.invalidateCamera()
            let failure = (error as? MeshSourcePresentationRenderError)
                ?? MeshSourcePresentationRenderError(code: .failed, message: error.localizedDescription)
            mount.report(failure, gridError: nil, gridReadout: nil, boundsRulerAxes: nil,
                         appliedRevision: viewport.appliedViewportRevision,
                         callback: onUpdateResult, gridCallback: onGridUpdateResult,
                         boundsRulerCallback: onBoundsRulerUpdateResult,
                         revisionCallback: onAppliedFrameRevision)
        }
    }

    /// Reference storage prevents native updates from invalidating SwiftUI body.
    @MainActor
    private final class Mount {
        var current: RealityViewport?
        private var lastError: MeshSourcePresentationRenderError?
        private var lastGridError: MeshSourcePresentationRenderError?
        private var lastGridReadout: ViewportProjectedGrid.ScaleReadout?
        private var lastBoundsRulerAxes: Set<ViewportMeasurementRulerAxis>?
        private var lastAppliedRevision: UInt64?
        private var hasReported = false
        private var reportsStatus = false
        private var reportsRevision = false
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
                      gridCallback: ((MeshSourcePresentationRenderError?, ViewportProjectedGrid.ScaleReadout?) -> Void)?,
                      boundsRulerCallback: ((Set<ViewportMeasurementRulerAxis>?) -> Void)?,
                      revisionCallback: ((UInt64?) -> Void)?) {
            pending = { [weak self] in
                guard let self, current === viewport,
                      viewport.isBound(to: ObjectIdentifier(self)) else { return true }
                do {
                    let error = try viewport.updateSpatialCamera(safeRect: safeRect, excludedRects: excludedRects,
                                                                gridRuler: gridRuler, gridSpacing: gridSpacing)
                    viewport.setPresentationEnabled(true)
                    report(nil, gridError: error, gridReadout: viewport.gridScaleReadout,
                           boundsRulerAxes: viewport.boundsRulerDisabledAxes,
                           appliedRevision: viewport.appliedViewportRevision,
                           callback: callback, gridCallback: gridCallback,
                           boundsRulerCallback: boundsRulerCallback,
                           revisionCallback: revisionCallback)
                    return true
                } catch RealityViewportSpatialResources.CameraReadinessError.projectionUnavailable {
                    viewport.setPresentationEnabled(false)
                    report(.init(code: .failed, message: "Waiting for the mounted native camera projection."),
                           gridError: nil, gridReadout: nil, boundsRulerAxes: nil,
                           appliedRevision: viewport.appliedViewportRevision,
                           callback: callback, gridCallback: gridCallback,
                           boundsRulerCallback: boundsRulerCallback,
                           revisionCallback: revisionCallback)
                    return false
                } catch {
                    viewport.invalidateCamera()
                    let failure = (error as? MeshSourcePresentationRenderError)
                        ?? MeshSourcePresentationRenderError(code: .failed, message: error.localizedDescription)
                    report(failure, gridError: nil, gridReadout: nil, boundsRulerAxes: nil,
                           appliedRevision: viewport.appliedViewportRevision,
                           callback: callback, gridCallback: gridCallback,
                           boundsRulerCallback: boundsRulerCallback,
                           revisionCallback: revisionCallback)
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

        /// Coalesces the status values and the applied camera revision.
        ///
        /// The status values keep their own change guard. The applied revision
        /// has none, because the same revision can belong to a different
        /// prepared frame after a surface is reused, and the mount cannot tell
        /// those apart; its receiver deduplicates on the content it derives.
        /// A pending notification survives the cancellation of its task
        /// because both flags live on the mount, not in the closure.
        func report(_ error: MeshSourcePresentationRenderError?, gridError: MeshSourcePresentationRenderError?,
                    gridReadout: ViewportProjectedGrid.ScaleReadout?,
                    boundsRulerAxes: Set<ViewportMeasurementRulerAxis>?, appliedRevision: UInt64?,
                    callback: @escaping (MeshSourcePresentationRenderError?) -> Void,
                    gridCallback: ((MeshSourcePresentationRenderError?, ViewportProjectedGrid.ScaleReadout?) -> Void)?,
                    boundsRulerCallback: ((Set<ViewportMeasurementRulerAxis>?) -> Void)?,
                    revisionCallback: ((UInt64?) -> Void)?) {
            let statusChanged = !hasReported || error != lastError
                || gridError != lastGridError || gridReadout != lastGridReadout
                || boundsRulerAxes != lastBoundsRulerAxes
            if statusChanged {
                hasReported = true
                lastError = error
                lastGridError = gridError
                lastGridReadout = gridReadout
                lastBoundsRulerAxes = boundsRulerAxes
                reportsStatus = true
            }
            lastAppliedRevision = appliedRevision
            reportsRevision = true
            reportTask?.cancel()
            reportTask = Task { @MainActor [weak self] in
                guard !Task.isCancelled, let self,
                      current?.isBound(to: ObjectIdentifier(self)) == true else { return }
                let deliversStatus = reportsStatus
                let deliversRevision = reportsRevision
                reportsStatus = false
                reportsRevision = false
                if deliversStatus {
                    callback(lastError)
                    gridCallback?(lastGridError, lastGridReadout)
                    boundsRulerCallback?(lastBoundsRulerAxes)
                }
                if deliversRevision { revisionCallback?(lastAppliedRevision) }
            }
        }

        func detach() {
            frameSubscription?.cancel()
            frameSubscription = nil
            pending = nil
            reportTask?.cancel()
            reportTask = nil
            // Owner-checked unbind also removes the root. A retiring mount
            // must not remove a root already adopted by its replacement.
            current?.unbind(owner: ObjectIdentifier(self))
            current = nil
            hasReported = false
            reportsStatus = false
            reportsRevision = false
            lastError = nil
            lastGridError = nil
            lastGridReadout = nil
            lastBoundsRulerAxes = nil
            lastAppliedRevision = nil
        }
    }
}
