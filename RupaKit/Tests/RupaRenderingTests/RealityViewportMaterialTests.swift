import AppKit
import Metal
import RealityKit
import SwiftCAD
import Testing
@testable import RupaRendering

@MainActor
@Test(.timeLimit(.minutes(1)))
func realityViewportMaterialUsesNativeAndCustomMaterialBoundaries() async throws {
    let materials = try await RealityViewportMaterial()
    let color = ColorRGBA(r: 0.25, g: 0.5, b: 0.75, a: 1)

    let studio = try materials.surface(
        displayMode: .solid,
        shading: ViewportShading(style: .studio),
        color: color
    )
    #expect(studio is PhysicallyBasedMaterial)

    let studioWithoutSpecular = try materials.surface(
        displayMode: .solid,
        shading: ViewportShading(style: .studio, isSpecularEnabled: false),
        color: color
    )
    let noSpecularPBR = try #require(studioWithoutSpecular as? PhysicallyBasedMaterial)
    #expect(noSpecularPBR.specular.scale == 0)

    let flat = try materials.surface(
        displayMode: .solidWithEdges,
        shading: ViewportShading(style: .flat),
        color: color
    )
    #expect(flat is UnlitMaterial)

    let wireframe = try materials.surface(
        displayMode: .wireframe,
        shading: ViewportShading(style: .studio),
        color: color
    )
    #expect(wireframe is OcclusionMaterial)

    let matCap = try materials.surface(
        displayMode: .solid,
        shading: ViewportShading(style: .matCap),
        color: color
    )
    #expect(matCap is CustomMaterial)

    let normals = try materials.surface(
        displayMode: .normals,
        shading: ViewportShading(style: .studio),
        color: color
    )
    #expect(normals is CustomMaterial)

    let line = materials.line(color: color)
    #expect(line.readsDepth)
    #expect(line.writesDepth)
}

@MainActor
@Test(.timeLimit(.minutes(1)))
func realityViewportMaterialRejectsInvalidColor() async throws {
    let materials = try await RealityViewportMaterial()

    #expect(throws: MeshSourcePresentationRenderError.self) {
        _ = try materials.surface(
            displayMode: .solid,
            shading: .standard,
            color: ColorRGBA(r: .nan, g: 0.5, b: 0.75, a: 1)
        )
    }
}

@MainActor
@Test(.timeLimit(.minutes(1)))
func realityViewportCustomMaterialExecutesOnNativeGPU() async throws {
    _ = NSApplication.shared
    let device = try #require(MTLCreateSystemDefaultDevice())
    let renderer = try RealityRenderer()
    renderer.cameraSettings.colorBackground = .color(CGColor(gray: 0, alpha: 1))
    renderer.cameraSettings.isToneMappingEnabled = false

    let camera = Entity()
    var lens = OrthographicCameraComponent()
    lens.near = 0.01
    lens.far = 100
    lens.scale = 2
    camera.components.set(lens)
    camera.position = [0, 0, 3]
    renderer.activeCamera = camera

    let materials = try await RealityViewportMaterial()
    let material = try materials.surface(
        displayMode: .solid,
        shading: ViewportShading(style: .matCap),
        color: ColorRGBA(r: 0.3, g: 0.65, b: 0.9, a: 1)
    )
    let box = ModelEntity(mesh: .generateBox(size: 0.8), materials: [material])
    renderer.entities.append(contentsOf: [camera, box])

    let descriptor = MTLTextureDescriptor.texture2DDescriptor(
        pixelFormat: .bgra8Unorm,
        width: 256,
        height: 256,
        mipmapped: false
    )
    descriptor.storageMode = .shared
    descriptor.usage = [.renderTarget, .shaderRead, .shaderWrite]
    let texture = try #require(device.makeTexture(descriptor: descriptor))
    let output = try RealityRenderer.CameraOutput(.singleProjection(colorTexture: texture))
    try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
        do {
            try renderer.updateAndRender(
                deltaTime: 1.0 / 60.0,
                cameraOutput: output,
                onComplete: { _ in continuation.resume() }
            )
        } catch {
            continuation.resume(throwing: error)
        }
    }

    var pixels = [UInt8](repeating: 0, count: 256 * 256 * 4)
    texture.getBytes(
        &pixels,
        bytesPerRow: 256 * 4,
        from: MTLRegionMake2D(0, 0, 256, 256),
        mipmapLevel: 0
    )
    let renderedPixels = stride(from: 0, to: pixels.count, by: 4).reduce(into: 0) { count, offset in
        if pixels[offset] > 8 || pixels[offset + 1] > 8 || pixels[offset + 2] > 8 {
            count += 1
        }
    }
    #expect(renderedPixels > 0)
}
