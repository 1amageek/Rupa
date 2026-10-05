import AppKit
import Metal
import RealityKit
import RupaCore
import SwiftCAD
import Testing
@testable import RupaRendering

@MainActor
@Test(.timeLimit(.minutes(1)))
func realityViewportMaterialUsesNativeAndCustomMaterialBoundaries() async throws {
    let materials = try await RealityViewportMaterial()
    let surface = ViewportSurface(
        color: ColorRGBA(r: 0.25, g: 0.5, b: 0.75, a: 1),
        authoring: nil
    )

    let studio = try materials.surface(
        displayMode: .solid,
        shading: ViewportShading(style: .studio),
        surface: surface
    )
    #expect(studio is PhysicallyBasedMaterial)

    let studioWithoutSpecular = try materials.surface(
        displayMode: .solid,
        shading: ViewportShading(style: .studio, isSpecularEnabled: false),
        surface: surface
    )
    let noSpecularPBR = try #require(studioWithoutSpecular as? PhysicallyBasedMaterial)
    #expect(noSpecularPBR.specular.scale == 0)

    let flat = try materials.surface(
        displayMode: .solidWithEdges,
        shading: ViewportShading(style: .flat),
        surface: surface
    )
    #expect(flat is UnlitMaterial)

    let wireframe = try materials.surface(
        displayMode: .wireframe,
        shading: ViewportShading(style: .studio),
        surface: surface
    )
    #expect(wireframe is OcclusionMaterial)

    let matCap = try materials.surface(
        displayMode: .solid,
        shading: ViewportShading(style: .matCap),
        surface: surface
    )
    #expect(matCap is CustomMaterial)

    let normals = try materials.surface(
        displayMode: .normals,
        shading: ViewportShading(style: .studio),
        surface: surface
    )
    #expect(normals is CustomMaterial)

    let line = materials.line(color: surface.color)
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
            surface: ViewportSurface(
                color: ColorRGBA(r: .nan, g: 0.5, b: 0.75, a: 1),
                authoring: nil
            )
        )
    }
}

@MainActor
@Test(.timeLimit(.minutes(1)))
func realityViewportMaterialRejectsAnOutOfRangeAuthoredComponent() async throws {
    let materials = try await RealityViewportMaterial()
    let color = ColorRGBA(r: 0.4, g: 0.5, b: 0.6, a: 1)

    #expect(throws: MeshSourcePresentationRenderError.self) {
        _ = try materials.surface(
            displayMode: .solid,
            shading: .standard,
            surface: ViewportSurface(color: color, opacity: 1, metallic: 1.4, roughness: 0.5)
        )
    }
    #expect(throws: MeshSourcePresentationRenderError.self) {
        _ = try materials.surface(
            displayMode: .solid,
            shading: .standard,
            surface: ViewportSurface(color: color, opacity: .nan, metallic: 0, roughness: 0.5)
        )
    }
}

@MainActor
@Test(.timeLimit(.minutes(1)))
func realityViewportMaterialRejectsInvalidPhysicalLayerBeforeNativeMutation() async throws {
    let materials = try await RealityViewportMaterial()
    let color = ColorRGBA(r: 0.4, g: 0.5, b: 0.6, a: 1)

    var invalidIOR = ViewportSurface(color: color, opacity: 1, metallic: 0, roughness: 0.5)
    invalidIOR.ior = 0.5
    #expect(throws: MeshSourcePresentationRenderError.self) {
        _ = try materials.surface(displayMode: .solid, shading: .standard, surface: invalidIOR)
    }

    var invalidSpecularColor = ViewportSurface(color: color, opacity: 1, metallic: 0, roughness: 0.5)
    invalidSpecularColor.specularColor = ColorRGBA(r: .infinity, g: 0, b: 0, a: 1)
    #expect(throws: MeshSourcePresentationRenderError.self) {
        _ = try materials.surface(displayMode: .solid, shading: .standard, surface: invalidSpecularColor)
    }

    var invalidThickness = ViewportSurface(color: color, opacity: 1, metallic: 0, roughness: 0.5)
    invalidThickness.thickness = -.ulpOfOne
    #expect(throws: MeshSourcePresentationRenderError.self) {
        _ = try materials.surface(displayMode: .solid, shading: .standard, surface: invalidThickness)
    }
}

@MainActor
@Test(.timeLimit(.minutes(1)))
func realityViewportMaterialBindsAdvancedAuthoredPayloadToNativeShader() async throws {
    let materials = try await RealityViewportMaterial()
    var surface = ViewportSurface(
        color: ColorRGBA(r: 0.4, g: 0.5, b: 0.6, a: 1),
        opacity: 0.8,
        metallic: 0.2,
        roughness: 0.35
    )
    surface.ior = 1.7
    surface.sheenRoughness = 0.35
    surface.specularColor = ColorRGBA(r: 0.8, g: 0.7, b: 0.6, a: 1)
    surface.iridescence = 0.25
    surface.iridescenceIOR = 1.4
    surface.thickness = 0
    surface.transmission = 0.3

    let material = try materials.surface(
        displayMode: .solid,
        shading: .standard,
        surface: surface
    )
    let custom = try #require(material as? CustomMaterial)
    #expect(custom.custom.texture != nil)
    #expect(custom.blending != .opaque)
}

@MainActor
@Test(.timeLimit(.minutes(1)), arguments: [0.0005, Double.greatestFiniteMagnitude])
func realityViewportMaterialRejectsUnsupportedTransmittingVolume(thickness: Double) async throws {
    let materials = try await RealityViewportMaterial()
    var surface = ViewportSurface(color: .init(r: 0.5, g: 0.5, b: 0.5, a: 1), opacity: 1, metallic: 0, roughness: 0.5)
    surface.thickness = thickness
    surface.transmission = 0.5
    do {
        _ = try materials.surface(displayMode: .solid, shading: .standard, surface: surface)
        Issue.record("A transmitting volume must fail until native volume transport exists.")
    } catch let error as MeshSourcePresentationRenderError {
        #expect(error.code == .gpuFailure)
        #expect(error.message == "RealityKit cannot render transmitting volume thickness.")
    }
    surface.transmission = 0
    let inactiveVolume = try materials.surface(displayMode: .solid, shading: .standard, surface: surface)
    #expect(inactiveVolume is PhysicallyBasedMaterial)
}

@MainActor
@Test(.timeLimit(.minutes(1)))
func realityViewportLitMaterialCarriesTheAuthoredMetallicAndRoughness() async throws {
    let materials = try await RealityViewportMaterial()
    let authored = SwiftCAD.Material(
        name: "Brushed steel",
        baseColor: ColorRGBA(r: 0.7, g: 0.72, b: 0.74, a: 1),
        metallic: 0.85,
        roughness: 0.22,
        opacity: 1
    )

    let authoredSurface = try materials.surface(
        displayMode: .solid,
        shading: ViewportShading(style: .studio),
        surface: ViewportSurface(color: authored.baseColor, authoring: authored)
    )
    let authoredPBR = try #require(authoredSurface as? PhysicallyBasedMaterial)
    #expect(authoredPBR.metallic.scale == Float(authored.metallic))
    #expect(authoredPBR.roughness.scale == Float(authored.roughness))

    // A body naming no material draws the neutral appearance, not the one the
    // previous body authored.
    let neutralSurface = try materials.surface(
        displayMode: .solid,
        shading: ViewportShading(style: .studio),
        surface: ViewportSurface(color: authored.baseColor, authoring: nil)
    )
    let neutralPBR = try #require(neutralSurface as? PhysicallyBasedMaterial)
    #expect(neutralPBR.metallic.scale == Float(SwiftCAD.Material.neutralMetallic))
    #expect(neutralPBR.roughness.scale == Float(SwiftCAD.Material.neutralRoughness))
}

@MainActor
@Test(.timeLimit(.minutes(1)))
func realityViewportSurfaceBlendsOnlyWhatTheDocumentMadeTransparent() async throws {
    let materials = try await RealityViewportMaterial()
    let color = ColorRGBA(r: 0.4, g: 0.5, b: 0.6, a: 1)
    let translucent = ViewportSurface(color: color, opacity: 0.35, metallic: 0, roughness: 0.5)
    let opaque = ViewportSurface(color: color, opacity: 1, metallic: 0, roughness: 0.5)

    let litTranslucentSurface = try materials.surface(
        displayMode: .solid,
        shading: ViewportShading(style: .studio),
        surface: translucent
    )
    let litTranslucent = try #require(litTranslucentSurface as? PhysicallyBasedMaterial)
    guard case .transparent(let litOpacity) = litTranslucent.blending else {
        Issue.record("The lit preset must blend a surface the document made translucent.")
        return
    }
    #expect(litOpacity.scale == 0.35)

    let litOpaqueSurface = try materials.surface(
        displayMode: .solid,
        shading: ViewportShading(style: .studio),
        surface: opaque
    )
    let litOpaque = try #require(litOpaqueSurface as? PhysicallyBasedMaterial)
    guard case .opaque = litOpaque.blending else {
        Issue.record("A fully opaque surface must stay out of the transparent pass.")
        return
    }

    let flatTranslucentSurface = try materials.surface(
        displayMode: .solid,
        shading: ViewportShading(style: .flat),
        surface: translucent
    )
    let flatTranslucent = try #require(flatTranslucentSurface as? UnlitMaterial)
    guard case .transparent(let flatOpacity) = flatTranslucent.blending else {
        Issue.record("The flat preset must blend a surface the document made translucent.")
        return
    }
    #expect(flatOpacity.scale == 0.35)

    let matCapTranslucentSurface = try materials.surface(
        displayMode: .solid,
        shading: ViewportShading(style: .matCap),
        surface: translucent
    )
    let matCapTranslucent = try #require(matCapTranslucentSurface as? CustomMaterial)
    // A custom material reconstructs this case from the program it was built
    // from and does not carry back the opacity it was assigned, so the case is
    // the evidence that the alpha-blended program was selected. What the
    // assigned opacity does to the rendered surface is proven on the GPU by
    // `realityViewportMatCapBlendsTheAuthoredOpacityOnNativeGPU`.
    guard case .transparent = matCapTranslucent.blending else {
        Issue.record("The MatCap program must blend a surface the document made translucent.")
        return
    }

    let matCapOpaqueSurface = try materials.surface(
        displayMode: .solid,
        shading: ViewportShading(style: .matCap),
        surface: opaque
    )
    let matCapOpaque = try #require(matCapOpaqueSurface as? CustomMaterial)
    guard case .opaque = matCapOpaque.blending else {
        Issue.record("A fully opaque MatCap surface must stay out of the transparent pass.")
        return
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
        surface: ViewportSurface(
            color: ColorRGBA(r: 0.3, g: 0.65, b: 0.9, a: 1),
            authoring: nil
        )
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

@Suite(.serialized)
struct RealityViewportAdvancedMaterialGPUSuite {
    @MainActor
    @Test(.timeLimit(.minutes(1)), arguments: AdvancedMaterialParameter.allCases)
    func realityViewportAdvancedMaterialPayloadChangesNativeGPUPixels(
        parameter: AdvancedMaterialParameter
    ) async throws {
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
        let box = ModelEntity(mesh: .generateBox(size: 0.8), materials: [])
        box.orientation = simd_quatf(angle: 0.6, axis: [0, 1, 0])
        // A lit studio surface needs illumination, as the production camera supplies.
        let light = DirectionalLight()
        light.light.intensity = 1_500
        light.orientation = simd_quatf(angle: -0.3, axis: [0, 1, 0])
        renderer.entities.append(contentsOf: [camera, box, light])

        let baseline = try await advancedMaterialMeanRGB(
            parameter: parameter, authored: false, renderer: renderer, box: box,
            device: device, materials: materials
        )
        let authored = try await advancedMaterialMeanRGB(
            parameter: parameter, authored: true, renderer: renderer, box: box,
            device: device, materials: materials
        )

        #expect(baseline.x + baseline.y + baseline.z > 0)
        #expect(authored.x + authored.y + authored.z > 0)
        let difference = SIMD3(abs(authored.x - baseline.x), abs(authored.y - baseline.y), abs(authored.z - baseline.z))
        #expect(max(difference.x, max(difference.y, difference.z)) > 0.01)
        if parameter == .specularColor {
            #expect(authored.y - authored.x > baseline.y - baseline.x)
        }
    }
}

enum AdvancedMaterialParameter: String, CaseIterable, Sendable {
    case ior
    case sheenColor
    case sheenRoughness
    case specularColor
    case specularIntensity
    case iridescence
    case iridescenceIOR
    case transmission
}

@MainActor
@Test(.timeLimit(.minutes(1)))
func realityViewportMatCapBlendsTheAuthoredOpacityOnNativeGPU() async throws {
    _ = NSApplication.shared
    let device = try #require(MTLCreateSystemDefaultDevice())
    let materials = try await RealityViewportMaterial()

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

    let box = ModelEntity(mesh: .generateBox(size: 0.8), materials: [])
    renderer.entities.append(contentsOf: [camera, box])

    // One offscreen renderer draws both cases. A second live `RealityRenderer`
    // in this process costs an already mounted viewport one published frame, so
    // the two frames here differ by the opacity the document authored and not
    // by the renderer that drew them.
    let opaque = try await matCapMeanLuminance(
        opacity: 1, renderer: renderer, box: box, device: device, materials: materials
    )
    let translucent = try await matCapMeanLuminance(
        opacity: 0.35, renderer: renderer, box: box, device: device, materials: materials
    )

    #expect(opaque > 0)
    // The opacity the document authored reaches the fragment, so over a black
    // background the translucent render lands near 0.35 of the opaque one.
    #expect(translucent / opaque > 0.30)
    #expect(translucent / opaque < 0.40)
}

/// Draws `box` at the supplied opacity with the supplied offscreen renderer and
/// reports the mean luminance of the rendered frame.
@MainActor
private func matCapMeanLuminance(
    opacity: Double,
    renderer: RealityRenderer,
    box: ModelEntity,
    device: any MTLDevice,
    materials: RealityViewportMaterial
) async throws -> Double {
    let material = try materials.surface(
        displayMode: .solid,
        shading: ViewportShading(style: .matCap),
        surface: ViewportSurface(
            color: ColorRGBA(r: 1, g: 1, b: 1, a: 1),
            opacity: opacity,
            metallic: 0,
            roughness: 0.5
        )
    )
    box.model?.materials = [material]

    let width = 256
    let height = 256
    let descriptor = MTLTextureDescriptor.texture2DDescriptor(
        pixelFormat: .bgra8Unorm,
        width: width,
        height: height,
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

    var pixels = [UInt8](repeating: 0, count: width * height * 4)
    texture.getBytes(
        &pixels,
        bytesPerRow: width * 4,
        from: MTLRegionMake2D(0, 0, width, height),
        mipmapLevel: 0
    )
    let total = stride(from: 0, to: pixels.count, by: 4).reduce(into: 0.0) { sum, offset in
        sum += Double(pixels[offset]) + Double(pixels[offset + 1]) + Double(pixels[offset + 2])
    }
    return total / Double(width * height * 3)
}

/// Draws one advanced material payload and reports its mean RGB components.
/// The renderer, camera, mesh, and base color remain unchanged between calls,
/// so a difference is evidence that the advanced payload reached the native
/// Metal surface rather than merely selecting a different Swift material type.
@MainActor
private func advancedMaterialMeanRGB(
    parameter: AdvancedMaterialParameter,
    authored: Bool,
    renderer: RealityRenderer,
    box: ModelEntity,
    device: any MTLDevice,
    materials: RealityViewportMaterial
) async throws -> SIMD3<Double> {
    var surface = ViewportSurface(
        color: ColorRGBA(r: 0.72, g: 0.48, b: 0.24, a: 1),
        opacity: 1,
        metallic: 0,
        roughness: 0.35
    )
    switch parameter {
    case .ior:
        surface.ior = authored ? 2.8 : 1.05
        surface.specularColor = .init(r: 1, g: 1, b: 1, a: 1)
        surface.specularIntensity = 1
        surface.transmission = 0.05
    case .sheenColor:
        surface.sheen = authored
            ? .init(r: 1, g: 0.85, b: 0.55, a: 1)
            : .init(r: 0, g: 0, b: 0, a: 1)
        surface.sheenRoughness = 0.35
        surface.transmission = 0.05
    case .sheenRoughness:
        surface.sheen = .init(r: 1, g: 0.85, b: 0.55, a: 1)
        surface.sheenRoughness = authored ? 0.1 : 0.9
        surface.transmission = 0.05
    case .specularColor:
        surface.ior = 2
        // Equal luminance, distinct RGB: reducing this payload to luminance fails.
        surface.specularColor = authored
            ? .init(r: 0, g: 0.2126 / 0.7152, b: 0, a: 1)
            : .init(r: 1, g: 0, b: 0, a: 1)
        surface.specularIntensity = 1
        surface.transmission = 0.05
    case .specularIntensity:
        surface.ior = 2
        surface.specularColor = .init(r: 1, g: 0.9, b: 0.8, a: 1)
        surface.specularIntensity = authored ? 1 : 0
        surface.transmission = 0.05
    case .iridescence:
        surface.iridescence = authored ? 1 : 0
        surface.iridescenceIOR = 2.8
        surface.transmission = 0.05
    case .iridescenceIOR:
        surface.iridescence = 1
        surface.iridescenceIOR = authored ? 2.8 : 1.1
        surface.transmission = 0.05
    case .transmission:
        surface.transmission = authored ? 0.8 : 0.05
    }
    let material = try materials.surface(
        displayMode: .solid,
        shading: ViewportShading(style: .studio),
        surface: surface
    )
    box.model?.materials = [material]

    let width = 256
    let height = 256
    let descriptor = MTLTextureDescriptor.texture2DDescriptor(
        pixelFormat: .bgra8Unorm,
        width: width,
        height: height,
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

    var pixels = [UInt8](repeating: 0, count: width * height * 4)
    texture.getBytes(
        &pixels,
        bytesPerRow: width * 4,
        from: MTLRegionMake2D(0, 0, width, height),
        mipmapLevel: 0
    )
    let total = stride(from: 0, to: pixels.count, by: 4).reduce(into: SIMD3<Double>.zero) { sum, offset in
        sum += SIMD3(Double(pixels[offset + 2]), Double(pixels[offset + 1]), Double(pixels[offset]))
    }
    return total / Double(width * height)
}
