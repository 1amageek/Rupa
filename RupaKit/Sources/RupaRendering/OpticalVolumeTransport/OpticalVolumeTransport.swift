import Foundation
import Metal
import RealityKit
import simd

/// Immutable scene and pipelines; each native frame captures its own camera.
@MainActor
final class OpticalVolumeTransport {
    let scene: OpticalVolumeScene
    private let pipeline: any MTLComputePipelineState
    private let publicationPipeline: any MTLComputePipelineState
    private let mediumCapacity: UInt32
    private let images: OpticalVolumeFrameStore
    private(set) var status = OpticalVolumeFrameStatus()
    private var capturedSource: OpticalVolumeFrameCapture?
    private var capturedEffect: OpticalVolumeEffect?

    init(triangles: [OpticalVolumeTriangle], opticalOccurrenceIndices: [UInt32], limits: OpticalVolumeLimits,
         previous: OpticalVolumeTransport?, images: OpticalVolumeFrameStore) throws {
        guard !opticalOccurrenceIndices.isEmpty, opticalOccurrenceIndices.count <= Int(UInt32.max),
              let device = MTLCreateSystemDefaultDevice() else {
            throw MeshSourcePresentationRenderError(code: .gpuUnavailable, message: "Optical transport requires an addressable scene and Metal device.")
        }
        let library: any MTLLibrary
        do { library = try device.makeDefaultLibrary(bundle: .module) }
        catch { throw MeshSourcePresentationRenderError(code: .gpuFailure, message: "Optical Metal library load failed: \(error.localizedDescription)") }
        guard let transport = library.makeFunction(name: "rupaOpticalVolumeTransport"),
              let publish = library.makeFunction(name: "rupaOpticalVolumePublish") else {
            throw MeshSourcePresentationRenderError(code: .gpuFailure, message: "Optical original-ray Metal entry points are absent.")
        }
        do {
            pipeline = try device.makeComputePipelineState(function: transport)
            publicationPipeline = try device.makeComputePipelineState(function: publish)
        } catch {
            throw MeshSourcePresentationRenderError(code: .gpuFailure, message: "Optical pipeline creation failed: \(error.localizedDescription)")
        }
        scene = try OpticalVolumeScene(triangles: triangles, opticalOccurrenceIndices: opticalOccurrenceIndices, device: device, limits: limits, images: images)
        mediumCapacity = UInt32(opticalOccurrenceIndices.count)
        self.images = images
    }

    func effect(worldFromView: simd_float4x4, section: RealityViewportSectionHalfSpace?, shading: ViewportShading, nativeSurfaceVisible: Bool, cameraRevision: UInt64?, viewportSize: CGSize?, displayScale: CGFloat?) throws -> OpticalVolumeEffect {
        guard (0..<4).allSatisfy({ column in (0..<4).allSatisfy { worldFromView[column][$0].isFinite } }) else {
            throw MeshSourcePresentationRenderError(code: .invalidTransform, message: "Optical camera transform is not finite.")
        }
        let clip: SIMD4<Float>
        if let section {
            clip = [Float(section.normal.x), Float(section.normal.y), Float(section.normal.z), Float(section.offset - section.tolerance)]
            guard (0..<4).allSatisfy({ clip[$0].isFinite }) else {
                throw MeshSourcePresentationRenderError(code: .invalidTransform, message: "Optical section exceeds native precision.")
            }
        } else { clip = [0, 0, 0, 0] }
        let background = try ViewportCanvasBackground.linearRGBA(for: shading.background)
        let rotation = Float(shading.studioRotationDegrees * .pi / 180)
        let capture = OpticalVolumeFrameCapture(worldFromView: worldFromView, section: clip, background: background,
            rotation: rotation, specular: shading.isSpecularEnabled, nativeSurfaceVisible: nativeSurfaceVisible, cameraRevision: cameraRevision,
            viewportSize: viewportSize, displayScale: displayScale)
        if capturedSource == capture, let capturedEffect { try status.check(); return capturedEffect }
        let nextStatus = OpticalVolumeFrameStatus()
        let effect = OpticalVolumeEffect(scene: scene, pipeline: pipeline, publicationPipeline: publicationPipeline,
            images: images, worldFromView: worldFromView, section: clip, background: background,
            studioRotation: rotation,
            specularEnabled: shading.isSpecularEnabled, nativeSurfaceVisible: nativeSurfaceVisible, mediumCapacity: mediumCapacity, status: nextStatus)
        capturedSource = capture
        capturedEffect = effect
        status = nextStatus
        return effect
    }

    var hasFailure: Bool { status.failure != nil }
}
