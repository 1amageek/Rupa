#include <metal_stdlib>
#include <RealityKit/RealityKit.h>
using namespace metal;

static half3 rupaTint(realitykit::surface_parameters params) {
    return half3(params.material_constants().base_color_tint());
}

static half3 rupaMatCapColor(float3 normal) {
    // Match the legacy 32x32 MatCap texture analytically. The texture used
    // view-normal XY as a sphere lookup and encoded this directional light:
    // base=(28,42,58)/255, scale=(138,156,178)/255.
    float2 sphere = clamp(normal.xy * 0.5 + 0.5, 0.0, 1.0) * 2.0 - 1.0;
    float radiusSquared = dot(sphere, sphere);
    float sphereZ = sqrt(max(0.0, 1.0 - radiusSquared));
    float highlight = clamp(
        max(0.0, 0.35 * sphere.x - 0.28 * sphere.y + 0.76 * sphereZ),
        0.0,
        1.0
    );
    half3 base = half3(28.0h / 255.0h, 42.0h / 255.0h, 58.0h / 255.0h);
    half3 scale = half3(138.0h / 255.0h, 156.0h / 255.0h, 178.0h / 255.0h);
    return base + scale * half(highlight);
}

[[visible]]
void rupaMatCapSurface(realitykit::surface_parameters params) {
    float3 normal = normalize(params.geometry().normal());
    float4x4 modelToView = params.uniforms().model_to_view();
    float3x3 normalMatrix = float3x3(
        modelToView[0].xyz,
        modelToView[1].xyz,
        modelToView[2].xyz
    );
    float3 viewNormal = normalize(normalMatrix * normal);
    params.surface().set_emissive_color(rupaTint(params) * rupaMatCapColor(viewNormal));
}

[[visible]]
void rupaNormalsSurface(realitykit::surface_parameters params) {
    float3 normal = normalize(params.geometry().normal());
    params.surface().set_emissive_color(half3(normal * 0.5 + 0.5));
}
