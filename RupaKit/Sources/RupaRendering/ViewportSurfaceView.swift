import AppKit
import MetalKit
import RupaCore
import RupaViewportScene
import SwiftUI

/// Native surface-only layer. Canvas and the input surface retain UI ownership.
struct ViewportSurfaceView: NSViewRepresentable {
    let renderer: ViewportSurfaceRenderer
    var displayMode: ViewportDisplayMode = .solid
    let layout: ViewportLayout
    let interaction: MeshSourcePresentationInteractionStateResolver
    let sectionPlane: SectionAnalysisResult.Plane?
    let retainedSide: SectionAnalysisRetainedSide
    let sectionTolerance: Double
    let onDrawResult: (MeshSourcePresentationRenderError?) -> Void

    func makeNSView(context: Context) -> SurfaceView {
        SurfaceView(frame: .zero, device: renderer.device)
    }

    func updateNSView(_ view: SurfaceView, context: Context) {
        view.input = self
        view.needsDisplay = true
    }

    static func dismantleNSView(_ view: SurfaceView, coordinator: ()) {
        view.input = nil
        view.delegate = nil
    }

    @MainActor
    final class SurfaceView: MTKView, MTKViewDelegate {
        var input: ViewportSurfaceView?
        private var inFlight = false
        private var redrawPending = false

        override var isOpaque: Bool { false }
        override func hitTest(_ point: NSPoint) -> NSView? { nil }

        override init(frame: NSRect, device: (any MTLDevice)?) {
            super.init(frame: frame, device: device)
            colorPixelFormat = .bgra8Unorm
            depthStencilPixelFormat = .depth32Float
            clearColor = MTLClearColorMake(0, 0, 0, 0)
            clearDepth = 1
            isPaused = true
            enableSetNeedsDisplay = true
            autoResizeDrawable = false
            framebufferOnly = true
            layer?.isOpaque = false
            if let metalLayer = layer as? CAMetalLayer {
                metalLayer.maximumDrawableCount = 2
            }
            delegate = self
        }

        required init(coder: NSCoder) {
            fatalError("SurfaceView is constructed programmatically.")
        }

        func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {}

        func reportDrawResult(
            error: MeshSourcePresentationRenderError?,
            for renderer: ViewportSurfaceRenderer
        ) {
            guard let input, input.renderer === renderer else { return }
            input.onDrawResult(error)
        }

        func draw(in view: MTKView) {
            guard let input, window != nil else { return }
            guard !inFlight else {
                redrawPending = true
                return
            }
            let scale = window?.backingScaleFactor ?? 1
            let width = ceil(bounds.width * scale)
            let height = ceil(bounds.height * scale)
            guard width > 0, height > 0 else { return }
            do {
                guard width.isFinite, height.isFinite, width <= 16_384, height <= 16_384 else {
                    throw MeshSourcePresentationRenderError(
                        code: .resourceExhausted, message: "Surface drawable dimensions exceed Metal limits."
                    )
                }
                _ = try ViewportSurfaceRenderer.attachmentByteCount(width: Int(width), height: Int(height))
                let size = CGSize(width: width, height: height)
                if drawableSize != size { drawableSize = size }
                guard let pass = currentRenderPassDescriptor, let drawable = currentDrawable else {
                    // An occluded/minimized window has no drawable. AppKit will
                    // invalidate the view on exposure; this is not empty geometry.
                    return
                }
                let commandBuffer = try input.renderer.makeCommandBuffer()
                let interval = ViewportResponsivenessSignposts.signposter.beginInterval(
                    "ViewportSurfaceEncoding", id: ViewportResponsivenessSignposts.signposter.makeSignpostID()
                )
                defer {
                    ViewportResponsivenessSignposts.signposter.endInterval("ViewportSurfaceEncoding", interval)
                }
                try input.renderer.encode(
                    into: commandBuffer, pass: pass, layout: input.layout,
                    displayMode: input.displayMode,
                    state: { input.interaction.state(for: $0) },
                    sectionPlane: input.sectionPlane, retainedSide: input.retainedSide,
                    sectionTolerance: input.sectionTolerance
                )
                commandBuffer.present(drawable)
                inFlight = true
                let submittedRenderer = input.renderer
                commandBuffer.addCompletedHandler { [weak self] buffer in
                    let failure: MeshSourcePresentationRenderError? = buffer.status == .error
                        ? MeshSourcePresentationRenderError(
                            code: .gpuFailure,
                            message: buffer.error?.localizedDescription ?? "Surface GPU execution failed."
                        ) : nil
                    Task { @MainActor [weak self] in
                        guard let self else { return }
                        self.inFlight = false
                        self.reportDrawResult(error: failure, for: submittedRenderer)
                        if self.redrawPending {
                            self.redrawPending = false
                            self.needsDisplay = true
                        }
                    }
                }
                commandBuffer.commit()
            } catch let error as MeshSourcePresentationRenderError {
                reportDrawResult(error: error, for: input.renderer)
            } catch {
                reportDrawResult(
                    error: MeshSourcePresentationRenderError(
                        code: .gpuFailure, message: String(describing: error)
                    ),
                    for: input.renderer
                )
            }
        }
    }
}
