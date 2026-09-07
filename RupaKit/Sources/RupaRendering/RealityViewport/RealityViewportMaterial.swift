import AppKit
import Foundation
import Metal
import RealityKit
import SwiftCAD

/// Owns the native RealityKit material policy for one mounted viewport.
///
/// Built-in materials are the default path. Custom materials are reserved for
/// MatCap and signed-normal presentation because RealityKit does not provide
/// those two viewport responses as built-in material modes. Section clipping is
/// owned by the mounted scene's native `ClippingComponent` and is therefore not
/// represented by a material parameter or shader fallback here.
@MainActor
struct RealityViewportMaterial {
    private let matCapProgram: CustomMaterial.Program
    private let normalsProgram: CustomMaterial.Program

    /// Loads the package Metal library and asynchronously prepares the two
    /// custom RealityKit programs required by the viewport.
    ///
    /// Native program generation is allowed to suspend. No entity or scene
    /// mutation is performed by this initializer, and callers must check their
    /// request identity after the await before publishing the resulting
    /// material owner.
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

        let matCapShader = CustomMaterial.SurfaceShader(named: matCapFunction, in: library)
        let normalsShader = CustomMaterial.SurfaceShader(named: normalsFunction, in: library)
        var descriptor = CustomMaterial.Program.Descriptor()
        descriptor.lightingModel = .unlit

        try Task.checkCancellation()
        let generatedMatCap: CustomMaterial.Program
        do {
            generatedMatCap = try await CustomMaterial.Program(
                surfaceShader: matCapShader,
                geometryModifier: nil,
                descriptor: descriptor
            )
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            throw Self.failure(
                .gpuFailure,
                "RealityKit custom material programs could not be generated: \(error.localizedDescription)"
            )
        }

        try Task.checkCancellation()
        let generatedNormals: CustomMaterial.Program
        do {
            generatedNormals = try await CustomMaterial.Program(
                surfaceShader: normalsShader,
                geometryModifier: nil,
                descriptor: descriptor
            )
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            throw Self.failure(
                .gpuFailure,
                "RealityKit custom material programs could not be generated: \(error.localizedDescription)"
            )
        }

        try Task.checkCancellation()
        matCapProgram = generatedMatCap
        normalsProgram = generatedNormals
    }

    /// Returns the native material for a triangle-surface entity.
    ///
    /// Section clipping is intentionally absent from this API. The scene owner
    /// applies the native RealityKit clipping component to the relevant root,
    /// so the material policy remains independent of section geometry and
    /// cannot silently diverge from native depth behavior.
    func surface(
        displayMode: ViewportDisplayMode,
        shading: ViewportShading,
        color: ColorRGBA
    ) throws -> any RealityKit.Material {
        do {
            try shading.validate()
        } catch let error as ViewportShadingError {
            throw Self.failure(.invalidLimit, error.localizedDescription)
        }
        try Self.validate(color: color, field: "surface color")

        switch displayMode {
        case .wireframe:
            return Self.makeOcclusionMaterial()
        case .normals:
            return makeCustomMaterial(
                program: normalsProgram,
                color: color,
                shading: shading,
                displayMode: displayMode
            )
        case .solid, .solidWithEdges:
            switch shading.style {
            case .studio:
                return Self.makeStudioMaterial(
                    color: color,
                    shading: shading,
                    displayMode: displayMode
                )
            case .matCap:
                return makeCustomMaterial(
                    program: matCapProgram,
                    color: color,
                    shading: shading,
                    displayMode: displayMode
                )
            case .flat:
                return Self.makeUnlitMaterial(
                    color: color,
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
        program: CustomMaterial.Program,
        color: ColorRGBA,
        shading: ViewportShading,
        displayMode: ViewportDisplayMode
    ) -> CustomMaterial {
        var material = CustomMaterial(program: program)
        material.baseColor = .init(tint: Self.nsColor(color))
        material.faceCulling = shading.isBackfaceCullingActive(in: displayMode) ? .back : .none
        material.readsDepth = true
        material.writesDepth = true
        return material
    }

    private static func makeStudioMaterial(
        color: ColorRGBA,
        shading: ViewportShading,
        displayMode: ViewportDisplayMode
    ) -> any RealityKit.Material {
        var material = PhysicallyBasedMaterial()
        material.baseColor = .init(tint: nsColor(color))
        material.metallic = 0.0
        material.roughness = shading.isSpecularEnabled ? 0.38 : 0.82
        // SimpleMaterial cannot disable dielectric specular response. Keep
        // the explicit viewport toggle exact with the native PBR parameter.
        material.specular = shading.isSpecularEnabled ? 0.9 : 0.0
        material.faceCulling = shading.isBackfaceCullingActive(in: displayMode) ? .back : .none
        material.readsDepth = true
        material.writesDepth = true
        return material
    }

    private static func makeUnlitMaterial(
        color: ColorRGBA,
        shading: ViewportShading,
        displayMode: ViewportDisplayMode
    ) -> UnlitMaterial {
        var material = UnlitMaterial(color: nsColor(color))
        material.faceCulling = shading.isBackfaceCullingActive(in: displayMode) ? .back : .none
        material.readsDepth = true
        material.writesDepth = true
        return material
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
