import simd

/// Metal-compatible immutable original display triangle and occurrence material.
struct OpticalVolumeTriangle: Hashable, Sendable {
    var first: SIMD4<Float>
    var second: SIMD4<Float>
    var third: SIMD4<Float>
    var baseColor: SIMD4<Float>
    var optics: SIMD4<Float>
    var finish: SIMD4<Float>
    var specular: SIMD4<Float>
    var sheen: SIMD4<Float>
    var coating: SIMD4<Float>
    var shadingNormal: SIMD4<Float>
    var identity: SIMD4<UInt32>

    init(first: SIMD3<Float>, second: SIMD3<Float>, third: SIMD3<Float>,
         normal: SIMD3<Float>, surface: ViewportSurface, occurrenceIndex: UInt32) throws {
        let numeric = [surface.color.r, surface.color.g, surface.color.b, surface.opacity,
                       surface.ior, surface.transmission, surface.thickness, surface.metallic,
                       surface.roughness, surface.specularIntensity, surface.clearcoat,
                       surface.clearcoatRoughness, surface.specularColor.r, surface.specularColor.g,
                       surface.specularColor.b, surface.sheen.r, surface.sheen.g, surface.sheen.b,
                       surface.sheenRoughness, surface.iridescence, surface.iridescenceIOR]
        guard numeric.allSatisfy({ $0.isFinite && Float($0).isFinite }),
              (0..<3).allSatisfy({ first[$0].isFinite && second[$0].isFinite && third[$0].isFinite }),
              (0..<3).allSatisfy({ normal[$0].isFinite }), simd_length_squared(normal) > 0,
              surface.thickness == 0 || Float(surface.thickness) > 0 else {
            throw MeshSourcePresentationRenderError(code: .invalidTransform,
                message: "Optical material or geometry exceeds native Float representation.")
        }
        self.first = SIMD4(first, 0)
        self.second = SIMD4(second, 0)
        self.third = SIMD4(third, 0)
        baseColor = try OpticalVolumeColor.linear(red: surface.color.r, green: surface.color.g,
            blue: surface.color.b, alpha: surface.opacity)
        optics = [Float(surface.ior), Float(surface.transmission), Float(surface.thickness), Float(surface.metallic)]
        finish = [Float(surface.roughness), Float(surface.opacity), Float(surface.specularIntensity), Float(surface.clearcoat)]
        specular = try OpticalVolumeColor.linear(red: surface.specularColor.r, green: surface.specularColor.g,
            blue: surface.specularColor.b, alpha: surface.clearcoatRoughness)
        sheen = try OpticalVolumeColor.linear(red: surface.sheen.r, green: surface.sheen.g,
            blue: surface.sheen.b, alpha: surface.sheenRoughness)
        coating = [Float(surface.iridescence), Float(surface.iridescenceIOR), 0, 0]
        shadingNormal = SIMD4(normal, 0)
        identity = [occurrenceIndex, 0, 0, 0]
    }

    init(primitive: RealityViewportSpatialResources.OpticalPrimitive, linearRadiance: SIMD4<Float>? = nil) throws {
        // FIXME(INCOMPLETE_IMPLEMENTATION): A legacy center-line payload does not
        // contain its native raster coverage. Mounted optical publication consumes
        // retained triangle packets from the native ribbon producer; a center-line
        // payload cannot succeed until it supplies that same drawn triangle authority.
        guard case .triangle = primitive.topology else {
            throw MeshSourcePresentationRenderError(code: .invalidSceneItem,
                message: "Optical center-line input requires its retained native raster triangles.")
        }
        guard (0..<3).allSatisfy({ primitive.first[$0].isFinite && primitive.second[$0].isFinite && primitive.third[$0].isFinite }),
              (0..<4).allSatisfy({ primitive.radiance[$0].isFinite }),
              primitive.radiance.w >= 0, primitive.radiance.w <= 1 else {
            throw MeshSourcePresentationRenderError(code: .invalidSceneItem,
                message: "Optical spatial primitive has invalid original geometry or appearance.")
        }
        first = SIMD4(primitive.first, 0)
        second = SIMD4(primitive.second, 0)
        third = SIMD4(primitive.third, 0)
        baseColor = try linearRadiance ?? OpticalVolumeColor.spatialLinear(primitive.radiance)
        optics = [1, 0, 0, 0]
        finish = [1, primitive.radiance.w, 0, 0]
        specular = .zero
        sheen = .zero
        coating = .zero
        shadingNormal = .zero
        // Spatial primitives own their original unlit radiance and depth/section laws.
        identity = [UInt32.max, 1 | (primitive.followsSection ? 2 : 0) | (primitive.readsDepth ? 4 : 0), 0, 0]
    }

    var minimum: SIMD3<Float> { simd_min(first.xyz, simd_min(second.xyz, third.xyz)) }
    var maximum: SIMD3<Float> { simd_max(first.xyz, simd_max(second.xyz, third.xyz)) }
}

private extension SIMD4 where Scalar == Float {
    var xyz: SIMD3<Float> { SIMD3(x, y, z) }
}
