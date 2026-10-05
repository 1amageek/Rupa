import AppKit
import Foundation
import Metal
import RealityKit
import SwiftCAD

/// Owns the native RealityKit material policy for one mounted viewport.
///
/// Built-in materials are the default path. Custom materials own MatCap,
/// signed-normal presentation, and the bounded advanced studio payload that
/// RealityKit's native PBR material cannot represent. Section clipping is
/// owned by the mounted scene's native `ClippingComponent` and is therefore not
/// represented by a material parameter or shader fallback here.
@MainActor
struct RealityViewportMaterial {
    private let matCapPrograms: BlendedPrograms
    private let normalsPrograms: BlendedPrograms
    private let advancedStudioPrograms: BlendedPrograms

    /// The two compilations of one custom surface shader.
    ///
    /// A custom material is blended by the blend mode its program was compiled
    /// with rather than by what is assigned to the material value, so the
    /// opaque and the alpha-blended response are two programs and not two
    /// values of one. See `RealityViewport/DESIGN.md`.
    private struct BlendedPrograms {
        let opaque: CustomMaterial.Program
        let alpha: CustomMaterial.Program

        func program(transparent: Bool) -> CustomMaterial.Program {
            transparent ? alpha : opaque
        }
    }

    /// Loads the package Metal library and asynchronously prepares the six
    /// custom RealityKit programs required by the viewport.
    ///
    /// Native program generation is allowed to suspend. Resolving a surface
    /// cannot, so both blend compilations of all custom shaders are prepared
    /// here rather than on first use. No entity or scene mutation is performed
    /// by this initializer, and callers must check their request identity after
    /// the await before publishing the resulting material owner.
    init() async throws {
        guard let device = MTLCreateSystemDefaultDevice() else {
            throw Self.failure(.gpuUnavailable, "RealityKit materials require a Metal device.")
        }

        let library: any MTLLibrary
        do {
            library = try device.makeDefaultLibrary(bundle: .module)
        } catch {
            throw Self.failure(
                .gpuFailure,
                "RealityKit material library could not be loaded: \(error.localizedDescription)"
            )
        }

        let matCapFunction = "rupaMatCapSurface"
        let normalsFunction = "rupaNormalsSurface"
        let advancedStudioFunction = "rupaAdvancedStudioSurface"
        guard library.makeFunction(name: matCapFunction) != nil else {
            throw Self.failure(
                .gpuFailure,
                "RealityKit material library is missing the \(matCapFunction) surface shader."
            )
        }
        guard library.makeFunction(name: normalsFunction) != nil else {
            throw Self.failure(
                .gpuFailure,
                "RealityKit material library is missing the \(normalsFunction) surface shader."
            )
        }
        guard library.makeFunction(name: advancedStudioFunction) != nil else {
            throw Self.failure(
                .gpuFailure,
                "RealityKit material library is missing the \(advancedStudioFunction) surface shader."
            )
        }

        let matCapShader = CustomMaterial.SurfaceShader(named: matCapFunction, in: library)
        let normalsShader = CustomMaterial.SurfaceShader(named: normalsFunction, in: library)
        let advancedStudioShader = CustomMaterial.SurfaceShader(named: advancedStudioFunction, in: library)

        matCapPrograms = try await Self.programs(for: matCapShader)
        normalsPrograms = try await Self.programs(for: normalsShader)
        advancedStudioPrograms = try await Self.programs(for: advancedStudioShader, lightingModel: .lit)
    }

    /// Compiles `shader` once for the opaque pass and once for alpha blending.
    ///
    /// The blend mode a custom material draws with is fixed when its program is
    /// compiled, so a shader that has to serve both an opaque and a translucent
    /// body is two programs rather than one value carrying two responses. See
    /// `RealityViewport/DESIGN.md`.
    private static func programs(
        for shader: CustomMaterial.SurfaceShader,
        lightingModel: CustomMaterial.LightingModel = .unlit
    ) async throws -> BlendedPrograms {
        var opaqueDescriptor = CustomMaterial.Program.Descriptor()
        opaqueDescriptor.lightingModel = lightingModel
        var alphaDescriptor = opaqueDescriptor
        alphaDescriptor.blendMode = .alpha
        let opaque = try await program(for: shader, descriptor: opaqueDescriptor)
        let alpha = try await program(for: shader, descriptor: alphaDescriptor)
        return BlendedPrograms(opaque: opaque, alpha: alpha)
    }

    private static func program(
        for shader: CustomMaterial.SurfaceShader,
        descriptor: CustomMaterial.Program.Descriptor
    ) async throws -> CustomMaterial.Program {
        try Task.checkCancellation()
        do {
            return try await CustomMaterial.Program(
                surfaceShader: shader,
                geometryModifier: nil,
                descriptor: descriptor
            )
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            throw failure(
                .gpuFailure,
                "RealityKit custom material programs could not be generated: \(error.localizedDescription)"
            )
        }
    }

    /// Returns the native material for a triangle-surface entity.
    ///
    /// The surface carries the base color the shading policy and any highlight
    /// decided together with the appearance the document authored, so the lit
    /// preset draws a metal as a metal rather than as a tinted default. The
    /// unlit, MatCap, normal, and advanced studio programs own their documented
    /// shading responses. See `RealityViewport/DESIGN.md`.
    ///
    /// Section clipping is intentionally absent from this API. The scene owner
    /// applies the native RealityKit clipping component to the relevant root,
    /// so the material policy remains independent of section geometry and
    /// cannot silently diverge from native depth behavior.
    func surface(
        displayMode: ViewportDisplayMode,
        shading: ViewportShading,
        surface: ViewportSurface,
        volumeTransportAvailable: Bool = false
    ) throws -> any RealityKit.Material {
        do {
            try shading.validate()
        } catch let error as ViewportShadingError {
            throw Self.failure(.invalidLimit, error.localizedDescription)
        }
        try Self.validate(surface, field: "surface")

        switch displayMode {
        case .wireframe:
            return Self.makeOcclusionMaterial()
        case .normals:
            return makeCustomMaterial(
                programs: normalsPrograms,
                surface: surface,
                shading: shading,
                displayMode: displayMode
            )
        case .solid, .solidWithEdges:
            switch shading.style {
            case .studio:
                guard surface.transmission == 0 || surface.thickness == 0 || volumeTransportAvailable else {
                    throw Self.failure(.gpuFailure, "Transmitting volume requires the original-scene optical producer.")
                }
                if surface.usesAdvancedMaterialShader {
                    return try makeAdvancedStudioMaterial(
                        surface: surface,
                        shading: shading,
                        displayMode: displayMode
                    )
                }
                return Self.makeStudioMaterial(surface: surface, shading: shading, displayMode: displayMode)
            case .matCap:
                return makeCustomMaterial(
                    programs: matCapPrograms,
                    surface: surface,
                    shading: shading,
                    displayMode: displayMode
                )
            case .flat:
                return Self.makeUnlitMaterial(
                    surface: surface,
                    shading: shading,
                    displayMode: displayMode
                )
            }
        }
    }

    /// Returns the native depth-tested material used by line topology.
    func line(color: ColorRGBA) -> UnlitMaterial {
        var material = UnlitMaterial(color: Self.nsColor(color))
        material.readsDepth = true
        material.writesDepth = true
        return material
    }

    private func makeCustomMaterial(
        programs: BlendedPrograms,
        surface: ViewportSurface,
        shading: ViewportShading,
        displayMode: ViewportDisplayMode
    ) -> CustomMaterial {
        let transparentOpacity = Self.transparentOpacity(of: surface)
        var material = CustomMaterial(
            program: programs.program(transparent: transparentOpacity != nil)
        )
        material.baseColor = .init(tint: Self.nsColor(surface.color))
        if let transparentOpacity {
            material.blending = .transparent(opacity: .init(floatLiteral: transparentOpacity))
        }
        material.faceCulling = shading.isBackfaceCullingActive(in: displayMode) ? .back : .none
        material.readsDepth = true
        material.writesDepth = true
        return material
    }

    private func makeAdvancedStudioMaterial(
        surface: ViewportSurface,
        shading: ViewportShading,
        displayMode: ViewportDisplayMode
    ) throws -> CustomMaterial {
        let transparentOpacity = Self.transparentOpacity(of: surface)
        var material = CustomMaterial(
            program: advancedStudioPrograms.program(transparent: transparentOpacity != nil)
        )
        material.baseColor = .init(tint: Self.nsColor(surface.color))
        material.metallic = .init(floatLiteral: Float(surface.metallic))
        material.roughness = .init(floatLiteral: Float(surface.roughness))
        let specularIntensity = shading.isSpecularEnabled ? surface.specularIntensity : 0
        material.specular = .init(floatLiteral: Float(specularIntensity))
        material.clearcoat = .init(floatLiteral: Float(surface.clearcoat))
        material.clearcoatRoughness = .init(floatLiteral: Float(surface.clearcoatRoughness))
        material.custom = .init(texture: try Self.advancedMaterialTexture(
            for: surface,
            specularIntensity: specularIntensity
        ))
        if let transparentOpacity {
            material.blending = .transparent(opacity: .init(floatLiteral: transparentOpacity))
        }
        material.faceCulling = shading.isBackfaceCullingActive(in: displayMode) ? .back : .none
        material.readsDepth = true
        material.writesDepth = true
        return material
    }

    private static func advancedMaterialTexture(
        for surface: ViewportSurface,
        specularIntensity: Double
    ) throws -> CustomMaterial.Texture {
        guard let device = MTLCreateSystemDefaultDevice() else {
            throw Self.failure(.gpuUnavailable, "RealityKit advanced material payload requires a Metal device.")
        }
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .rgba32Float,
            width: 4,
            height: 1,
            mipmapped: false
        )
        descriptor.usage = [.shaderRead]
        guard let texture = device.makeTexture(descriptor: descriptor) else {
            throw Self.failure(.gpuFailure, "RealityKit could not allocate the advanced material payload texture.")
        }
        let values: [Float] = [
            Float(surface.ior), Float(surface.iridescence), Float(surface.iridescenceIOR), 0,
            Float(surface.sheen.r), Float(surface.sheen.g), Float(surface.sheen.b), Float(surface.sheenRoughness),
            Float(surface.specularColor.r), Float(surface.specularColor.g), Float(surface.specularColor.b), Float(specularIntensity),
            Float(surface.transmission), Float(surface.displayedOpacity), 0, 0
        ]
        values.withUnsafeBytes { bytes in
            texture.replace(
                region: MTLRegionMake2D(0, 0, 4, 1),
                mipmapLevel: 0,
                withBytes: bytes.baseAddress!,
                bytesPerRow: values.count * MemoryLayout<Float>.stride
            )
        }
        return CustomMaterial.Texture(TextureResource.__texture(from: texture))
    }

    private static func makeStudioMaterial(
        surface: ViewportSurface,
        shading: ViewportShading,
        displayMode: ViewportDisplayMode
    ) -> any RealityKit.Material {
        var material = PhysicallyBasedMaterial()
        material.baseColor = .init(tint: nsColor(surface.color))
        // The lit preset is the one native material that carries all four
        // components, so the document's metallic and roughness reach the
        // canvas here rather than being approximated from the session preset.
        material.metallic = .init(floatLiteral: Float(surface.metallic))
        material.roughness = .init(floatLiteral: Float(surface.roughness))
        // SimpleMaterial cannot disable dielectric specular response. Keep
        // the explicit viewport toggle exact with the native PBR parameter,
        // scaled by the material's specular intensity.
        material.specular = .init(floatLiteral: shading.isSpecularEnabled ? Float(0.9 * surface.specularIntensity) : 0.0)
        material.clearcoat = .init(floatLiteral: Float(surface.clearcoat))
        material.clearcoatRoughness = .init(floatLiteral: Float(surface.clearcoatRoughness))
        // The advanced non-default fields select the custom studio shader before this
        // native path is reached. This branch therefore only receives the fields that
        // RealityKit's native PBR material represents directly.
        if surface.sheen.r > 0 || surface.sheen.g > 0 || surface.sheen.b > 0 {
            material.sheen = .init(tint: nsColor(surface.sheen))
        }
        if let opacity = transparentOpacity(of: surface) {
            material.blending = .transparent(opacity: .init(floatLiteral: opacity))
        }
        material.faceCulling = shading.isBackfaceCullingActive(in: displayMode) ? .back : .none
        material.readsDepth = true
        material.writesDepth = true
        return material
    }

    private static func makeUnlitMaterial(
        surface: ViewportSurface,
        shading: ViewportShading,
        displayMode: ViewportDisplayMode
    ) -> UnlitMaterial {
        var material = UnlitMaterial(color: nsColor(surface.color))
        if let opacity = transparentOpacity(of: surface) {
            material.blending = .transparent(opacity: .init(floatLiteral: opacity))
        }
        material.faceCulling = shading.isBackfaceCullingActive(in: displayMode) ? .back : .none
        material.readsDepth = true
        material.writesDepth = true
        return material
    }

    /// The native opacity a transparent surface blends with, or `nil` when the
    /// surface is opaque.
    ///
    /// A fully opaque surface keeps the native opaque blending, so authoring an
    /// appearance does not move every body into the transparent pass and change
    /// how the canvas sorts and depth-tests it. Each native material names its
    /// own `Blending` type, so the caller selects the case and this decides
    /// only whether there is one to select.
    private static func transparentOpacity(of surface: ViewportSurface) -> Float? {
        surface.isTransparent ? Float(surface.displayedOpacity) : nil
    }

    private static func makeOcclusionMaterial() -> OcclusionMaterial {
        var material = OcclusionMaterial(receivesDynamicLighting: false)
        // Occlusion is a native depth-only surface for wireframe visibility.
        material.faceCulling = .none
        material.readsDepth = true
        return material
    }

    static func validate(color: ColorRGBA, field: String) throws {
        let values = [color.r, color.g, color.b, color.a]
        guard values.allSatisfy({ $0.isFinite && (0...1).contains($0) }) else {
            throw Self.failure(.invalidLimit, "\(field) must contain finite components in 0...1.")
        }
    }

    /// Validates every component the document authored for `material`.
    ///
    /// The supplier validates its own domain, and this is the native boundary
    /// checking what actually reaches a RealityKit parameter, so an
    /// out-of-range component fails visibly here instead of being clamped.
    static func validate(_ material: SwiftCAD.Material, field: String) throws {
        try validate(color: material.baseColor, field: "\(field) base color")
        try validate(unitValue: material.opacity, field: "\(field) opacity")
        try validate(unitValue: material.metallic, field: "\(field) metallic")
        try validate(unitValue: material.roughness, field: "\(field) roughness")
        try validate(rangeValue: material.ior, range: 1...3, field: "\(field) ior")
        try validate(unitValue: material.clearcoat, field: "\(field) clearcoat")
        try validate(unitValue: material.clearcoatRoughness, field: "\(field) clearcoat roughness")
        try validate(unitValue: material.sheen, field: "\(field) sheen")
        try validate(color: material.sheenColor, field: "\(field) sheen color")
        try validate(unitValue: material.sheenRoughness, field: "\(field) sheen roughness")
        try validate(color: material.specularColor, field: "\(field) specular color")
        try validate(unitValue: material.specularIntensity, field: "\(field) specular intensity")
        try validate(unitValue: material.iridescence, field: "\(field) iridescence")
        try validate(rangeValue: material.iridescenceIOR, range: 1...3, field: "\(field) iridescence IOR")
        guard material.thickness.isFinite, material.thickness >= 0 else {
            throw Self.failure(.invalidLimit, "\(field) thickness must be finite and non-negative.")
        }
        try validate(unitValue: material.transmission, field: "\(field) transmission")
    }

    /// Validates one resolved surface before it reaches a native material.
    static func validate(_ surface: ViewportSurface, field: String) throws {
        try validate(color: surface.color, field: "\(field) color")
        try validate(unitValue: surface.opacity, field: "\(field) opacity")
        try validate(unitValue: surface.metallic, field: "\(field) metallic")
        try validate(unitValue: surface.roughness, field: "\(field) roughness")
        try validate(rangeValue: surface.ior, range: 1...3, field: "\(field) ior")
        try validate(unitValue: surface.clearcoat, field: "\(field) clearcoat")
        try validate(unitValue: surface.clearcoatRoughness, field: "\(field) clearcoat roughness")
        try validate(color: surface.sheen, field: "\(field) sheen")
        try validate(unitValue: surface.sheenRoughness, field: "\(field) sheen roughness")
        try validate(color: surface.specularColor, field: "\(field) specular color")
        try validate(unitValue: surface.specularIntensity, field: "\(field) specular intensity")
        try validate(unitValue: surface.iridescence, field: "\(field) iridescence")
        try validate(rangeValue: surface.iridescenceIOR, range: 1...3, field: "\(field) iridescence IOR")
        guard surface.thickness.isFinite, surface.thickness >= 0 else {
            throw Self.failure(.invalidLimit, "\(field) thickness must be finite and non-negative.")
        }
        try validate(unitValue: surface.transmission, field: "\(field) transmission")
    }

    static func validate(unitValue: Double, field: String) throws {
        guard unitValue.isFinite, (0...1).contains(unitValue) else {
            throw Self.failure(.invalidLimit, "\(field) must be a finite value in 0...1.")
        }
    }

    static func validate(rangeValue: Double, range: ClosedRange<Double>, field: String) throws {
        guard rangeValue.isFinite, range.contains(rangeValue) else {
            throw Self.failure(.invalidLimit, "\(field) must be finite and in \(range.lowerBound)...\(range.upperBound).")
        }
    }

    private static func nsColor(_ color: ColorRGBA) -> NSColor {
        NSColor(
            calibratedRed: CGFloat(color.r),
            green: CGFloat(color.g),
            blue: CGFloat(color.b),
            alpha: CGFloat(color.a)
        )
    }

    private static func failure(
        _ code: MeshSourcePresentationRenderError.Code,
        _ message: String
    ) -> MeshSourcePresentationRenderError {
        MeshSourcePresentationRenderError(code: code, message: message)
    }
}
