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
    let onUpdateResult: (MeshSourcePresentationRenderError?) -> Void
    @State private var mount = Mount()

    var body: some View {
        RealityView { content in
            content.camera = .virtual
            update(&content)
        } update: { content in
            update(&content)
        }
        .onDisappear { mount.detach() }
    }

    private func update(_ content: inout RealityViewCameraContent) {
        if mount.current !== viewport {
            mount.detach()
            for entity in content.entities { content.remove(entity) }
            content.add(viewport.root)
            mount.current = viewport
        }
        viewport.bind(content)
        do {
            try viewport.applyCamera(layout: layout, revision: viewportRevision)
            try viewport.applyAppearance(displayMode: displayMode, shading: shading,
                                         materialColors: materialColors, interaction: interaction,
                                         sectionPlane: sectionPlane, retainedSide: retainedSide, sectionTolerance: sectionTolerance)
            viewport.root.isEnabled = true
            mount.report(nil, callback: onUpdateResult)
        } catch {
            viewport.invalidateCamera()
            let failure = (error as? MeshSourcePresentationRenderError)
                ?? MeshSourcePresentationRenderError(code: .failed, message: error.localizedDescription)
            mount.report(failure, callback: onUpdateResult)
        }
    }

    /// Reference storage prevents native updates from invalidating SwiftUI body.
    @MainActor
    private final class Mount {
        var current: RealityViewport?
        private var lastError: MeshSourcePresentationRenderError?
        private var hasReported = false
        private var reportTask: Task<Void, Never>?

        func report(_ error: MeshSourcePresentationRenderError?, callback: @escaping (MeshSourcePresentationRenderError?) -> Void) {
            guard !hasReported || error != lastError else { return }
            hasReported = true
            lastError = error
            reportTask?.cancel()
            reportTask = Task { @MainActor in
                guard !Task.isCancelled else { return }
                callback(error)
            }
        }

        func detach() {
            reportTask?.cancel()
            reportTask = nil
            current?.unbind()
            current = nil
            hasReported = false
            lastError = nil
        }
    }
}
