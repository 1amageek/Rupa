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

constexpr sampler rupaAdvancedNearest(
    coord::normalized,
    address::clamp_to_edge,
    filter::nearest,
    mip_filter::none
);

[[visible]]
void rupaAdvancedStudioSurface(realitykit::surface_parameters params) {
    metal::texture2d<half> payload = params.textures().custom();
    // RealityKit exposes the custom texture as half; widen once for bounded float arithmetic.
    float4 film = float4(payload.sample(rupaAdvancedNearest, float2(0.125, 0.5)));
    float4 sheen = float4(payload.sample(rupaAdvancedNearest, float2(0.375, 0.5)));
    float4 specularColor = float4(payload.sample(rupaAdvancedNearest, float2(0.625, 0.5)));
    float4 transmission = float4(payload.sample(rupaAdvancedNearest, float2(0.875, 0.5)));

    float3 normal = normalize(params.geometry().normal());
    float3 viewDirection = normalize(params.geometry().view_direction());
    float normalView = saturate(dot(normal, viewDirection));
    float eta = (film.x - 1.0) / (film.x + 1.0);
    float baseReflectance = eta * eta;
    float grazing = 1.0 - normalView;
    float fresnel = baseReflectance + (1.0 - baseReflectance) * pow(grazing, 5.0);
    // A bounded angular viewport color response, not thin-film optical transport.
    // The source thickness is a transmitting volume and never enters this phase.
    float3 phase = 6.2831853 * (film.z - 1.0) * grazing * float3(1.0, 1.3, 1.7);
    float3 iridescentColor = 0.5 + 0.5 * cos(phase);
    float3 specularTint = specularColor.xyz * mix(float3(1.0), iridescentColor, film.y);
    float sheenWeight = max(sheen.x, max(sheen.y, sheen.z));
    float sheenViewWeight = sheenWeight * grazing;
    float roughness = mix(
        params.material_constants().roughness_scale(),
        sheen.w,
        sheenWeight * 0.5
    );
    float specular = saturate(specularColor.w * fresnel
        * mix(1.0, 0.5, saturate(transmission.x)));
    float3 baseColor = float3(params.material_constants().base_color_tint());
    float3 reflectedColor = mix(baseColor, specularTint, specular);
    float3 chromaticColor = mix(reflectedColor, sheen.xyz, sheenViewWeight);

    params.surface().set_base_color(half3(saturate(chromaticColor)));
    params.surface().set_metallic(half(params.material_constants().metallic_scale()));
    params.surface().set_roughness(half(saturate(roughness)));
    params.surface().set_specular(half(specular));
    params.surface().set_clearcoat(half(params.material_constants().clearcoat_scale()));
    params.surface().set_clearcoat_roughness(half(params.material_constants().clearcoat_roughness_scale()));
    params.surface().set_opacity(half(saturate(transmission.y)));
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

// The native postprocess consumes Float original-scene buffers, never the
// half-precision custom surface payload, for volume geometry and ray transport.
struct RupaOpticalTriangle {
    float4 first, second, third, baseColor, optics, finish, specular, sheen, coating, shadingNormal;
    uint4 identity;
};
struct RupaOpticalNode { float4 minimum, maximum; uint4 indices; };
struct RupaOpticalParameters {
    float4x4 worldFromView, viewFromWorld, projection, inverseProjection;
    float4 section;
    uint4 frame, limits;
    float4 studio, background;
};
struct RupaOpticalHit { float distance; float3 normal; uint triangle; bool sectionCap; };

static bool rupaOpticalConsumeWork(thread uint &work,
                                   constant RupaOpticalParameters &parameters,
                                   thread uint &failure) {
    if (failure != 0) return false;
    if (work >= parameters.limits.y) { failure = 1; return false; }
    ++work;
    return true;
}

static bool rupaOpticalBox(float3 origin, float3 direction, float3 minimum,
                           float3 maximum, float maximumDistance) {
    float lower = 0.0, upper = maximumDistance;
    for (uint axis = 0; axis < 3; ++axis) {
        if (direction[axis] == 0.0) {
            if (origin[axis] < minimum[axis] || origin[axis] > maximum[axis]) return false;
        } else {
            float a = (minimum[axis] - origin[axis]) / direction[axis];
            float b = (maximum[axis] - origin[axis]) / direction[axis];
            lower = max(lower, min(a, b));
            upper = min(upper, max(a, b));
            if (lower > upper) return false;
        }
    }
    return true;
}

static RupaOpticalHit rupaOpticalTrace(
    float3 origin, float3 direction, device const RupaOpticalTriangle *triangles,
    device const RupaOpticalNode *nodes, constant RupaOpticalParameters &parameters,
    thread uint &work, thread uint &failure, uint previousTriangle = UINT_MAX,
    uint occurrence = UINT_MAX, bool clip = true, uint depthMode = 0
) {
    RupaOpticalHit hit = {INFINITY, float3(0), UINT_MAX, false};
    uint node = 0;
    while (node < parameters.frame.w) {
        if (!rupaOpticalConsumeWork(work, parameters, failure)) return hit;
        RupaOpticalNode bounds = nodes[node];
        if (!rupaOpticalBox(origin, direction, bounds.minimum.xyz, bounds.maximum.xyz, hit.distance)) {
            node = bounds.indices.z;
            continue;
        }
        if (bounds.indices.y == 0) { ++node; continue; }
        for (uint offset = 0; offset < bounds.indices.y; ++offset) {
            if (!rupaOpticalConsumeWork(work, parameters, failure)) return hit;
            uint index = bounds.indices.x + offset;
            if (index == previousTriangle) continue;
            RupaOpticalTriangle triangle = triangles[index];
            if (triangle.finish.y == 0) continue;
            if (occurrence != UINT_MAX && triangle.identity.x != occurrence) continue;
            bool unlit = (triangle.identity.y & 1) != 0;
            bool nativeOverlay = unlit && (triangle.identity.y & 4) == 0;
            if ((depthMode == 1) != nativeOverlay) continue;
            float3 first = triangle.first.xyz;
            float3 a = triangle.second.xyz - first, b = triangle.third.xyz - first;
            float3 crossDirection = cross(direction, b);
            float determinant = dot(a, crossDirection);
            if (!all(isfinite(a)) || !all(isfinite(b)) || !all(isfinite(crossDirection))
                || !isfinite(determinant)) { failure = 3; return hit; }
            if (determinant == 0) continue;
            float3 delta = origin - first;
            float u = dot(delta, crossDirection) / determinant;
            if (!all(isfinite(delta)) || !isfinite(u)) { failure = 3; return hit; }
            if (u < 0 || u > 1) continue;
            float3 crossDelta = cross(delta, a);
            float v = dot(direction, crossDelta) / determinant;
            if (!all(isfinite(crossDelta)) || !isfinite(v)) { failure = 3; return hit; }
            if (v < 0 || u + v > 1) continue;
            float distance = dot(b, crossDelta) / determinant;
            if (!isfinite(distance)) { failure = 3; return hit; }
            if (!(distance > 0) || distance >= hit.distance) continue;
            float3 point = origin + direction * distance;
            if (!all(isfinite(point))) { failure = 3; return hit; }
            if (clip && (!unlit || (triangle.identity.y & 2) != 0) && dot(parameters.section.xyz, point) < parameters.section.w) continue;
            float3 normal = cross(a, b);
            float squared = dot(normal, normal);
            if (!isfinite(distance) || !isfinite(squared)) { failure = 3; return hit; }
            if (!(squared > 0)) continue;
            hit = {distance, normal / sqrt(squared), index, false};
        }
        node = bounds.indices.z;
    }
    return hit;
}

// Section caps are admitted by original closed-mesh incidence at the actual
// ray/plane point; no screen sample or fabricated bounding plane is a cap.
static RupaOpticalHit rupaOpticalVolumeTrace(
    float3 origin, float3 direction, device const RupaOpticalTriangle *triangles,
    device const RupaOpticalNode *nodes, constant RupaOpticalParameters &parameters,
    device const uint *opticalOccurrences, thread uint &work, thread uint &failure,
    uint previousTriangle = UINT_MAX, uint occurrence = UINT_MAX, bool clip = true,
    uint depthMode = 0
) {
    RupaOpticalHit hit = rupaOpticalTrace(origin, direction, triangles, nodes, parameters,
        work, failure, previousTriangle, occurrence, clip, depthMode);
    float lengthSquared = dot(parameters.section.xyz, parameters.section.xyz);
    if (failure != 0 || !clip || depthMode != 0 || lengthSquared == 0) return hit;
    float denominator = dot(parameters.section.xyz, direction);
    if (denominator == 0) return hit;
    float distance = (parameters.section.w - dot(parameters.section.xyz, origin)) / denominator;
    if (!isfinite(distance) || !(distance > 0) || distance >= hit.distance) return hit;
    float3 point = origin + direction * distance;
    for (uint index = 0; index < parameters.limits.z; ++index) {
        if (!rupaOpticalConsumeWork(work, parameters, failure)) return hit;
        uint owner = opticalOccurrences[index];
        if (occurrence != UINT_MAX && owner != occurrence) continue;
        RupaOpticalHit boundary = rupaOpticalTrace(point, direction, triangles, nodes, parameters,
            work, failure, UINT_MAX, owner, false);
        if (failure != 0) return hit;
        if (boundary.triangle == UINT_MAX || dot(direction, boundary.normal) <= 0) continue;
        hit = {distance, -parameters.section.xyz / sqrt(lengthSquared), boundary.triangle, true};
        break;
    }
    return hit;
}

static float3 rupaOpticalAdvance(float3 point, float3 direction) {
    for (uint axis = 0; axis < 3; ++axis) {
        if (direction[axis] != 0) point[axis] = nextafter(point[axis], copysign(INFINITY, direction[axis]));
    }
    return point;
}

static float3 rupaOpticalStudio(
    RupaOpticalTriangle triangle, float3 normal, float3 view,
    constant RupaOpticalParameters &parameters
) {
    normal = faceforward(normal, -view, normal);
    float3 viewNormal = normalize((parameters.viewFromWorld * float4(normal, 0)).xyz);
    float3 viewDirection = normalize((parameters.viewFromWorld * float4(view, 0)).xyz);
    float c = cos(parameters.studio.x), s = sin(parameters.studio.x);
    float3 directions[2] = {float3(-0.4, -0.6, -1), float3(0.7, 0.2, -1)};
    float intensities[2] = {3000.0 / 4200.0, 1200.0 / 4200.0};
    float roughness = max(triangle.finish.x, 0.001);
    float alpha2 = pow(roughness, 4.0);
    float eta = (triangle.optics.x - 1) / (triangle.optics.x + 1);
    float3 f0 = mix(float3(eta * eta) * triangle.specular.xyz * triangle.finish.z,
                   triangle.baseColor.xyz, triangle.optics.w);
    float3 result = float3(0);
    for (uint light = 0; light < 2; ++light) {
        float3 source = normalize(directions[light]);
        source.xy = float2(c * source.x - s * source.y, s * source.x + c * source.y);
        float3 incoming = -source;
        float cosine = saturate(dot(viewNormal, incoming));
        if (cosine == 0) continue;
        float3 halfVector = normalize(incoming + viewDirection);
        float nh = saturate(dot(viewNormal, halfVector));
        float nv = saturate(dot(viewNormal, viewDirection));
        float vh = saturate(dot(viewDirection, halfVector));
        float divisor = nh * nh * (alpha2 - 1) + 1;
        float distribution = alpha2 / (M_PI_F * divisor * divisor);
        float k = (roughness + 1) * (roughness + 1) / 8;
        float geometry = (nv / (nv * (1 - k) + k)) * (cosine / (cosine * (1 - k) + k));
        float3 fresnel = f0 + (1 - f0) * pow(1 - vh, 5.0);
        float3 diffuse = triangle.baseColor.xyz * (1 - triangle.optics.w) * (1 - triangle.optics.y) / M_PI_F;
        float3 specular = parameters.limits.w != 0 ? distribution * geometry * fresnel / max(4 * nv * cosine, FLT_MIN) : float3(0);
        float3 sheen = triangle.sheen.xyz * pow(1 - vh, 5.0) * (1 - triangle.sheen.w * 0.5);
        float coatEta = (1.5 - 1) / (1.5 + 1);
        float coat = triangle.finish.w * (coatEta * coatEta + (1 - coatEta * coatEta) * pow(1 - vh, 5.0));
        float3 phase = 2 * M_PI_F * (triangle.coating.y - 1) * (1 - vh) * float3(1, 1.3, 1.7);
        specular *= mix(float3(1), 0.5 + 0.5 * cos(phase), triangle.coating.x);
        result += (diffuse + specular + sheen + coat) * cosine * intensities[light];
    }
    return result;
}

static float4 rupaOpticalHitColor(
    RupaOpticalHit hit, float3 point, float3 direction,
    device const RupaOpticalTriangle *triangles,
    constant RupaOpticalParameters &parameters,
    texture2d<float, access::read> source, texture2d<float, access::read> depth
) {
    RupaOpticalTriangle triangle = triangles[hit.triangle];
    if ((triangle.identity.y & 1) != 0) return triangle.baseColor;
    float4 projected = parameters.projection * parameters.viewFromWorld * float4(point, 1);
    if (projected.w > 0) {
        float3 ndc = projected.xyz / projected.w;
        float2 pixel = float2((ndc.x * 0.5 + 0.5) * parameters.frame.x,
                             (0.5 - ndc.y * 0.5) * parameters.frame.y);
        if (all(pixel >= 0) && pixel.x < parameters.frame.x && pixel.y < parameters.frame.y) {
            uint2 coordinate = uint2(pixel);
            float originalDepth = depth.read(coordinate).x;
            // Admit one native raster depth quantum plus Float projection roundoff.
            float error = abs(nextafter(originalDepth, INFINITY) - originalDepth)
                        + abs(nextafter(ndc.z, INFINITY) - ndc.z);
            if (parameters.studio.w != 0 && abs(originalDepth - ndc.z) <= error) return source.read(coordinate);
        }
    }
    return float4(rupaOpticalStudio(triangle, hit.sectionCap ? hit.normal : triangle.shadingNormal.xyz, -direction, parameters), triangle.finish.y);
}

static uint rupaMediumRead(thread uint *local, device uint *global, uint index, uint capacity) {
    return capacity <= 4 ? local[index] : global[index];
}
static void rupaMediumWrite(thread uint *local, device uint *global, uint index, uint capacity, uint value) {
    if (capacity <= 4) local[index] = value; else global[index] = value;
}

kernel void rupaOpticalVolumeTransport(
    device const RupaOpticalTriangle *triangles [[buffer(0)]],
    device const RupaOpticalNode *nodes [[buffer(1)]],
    constant RupaOpticalParameters &parameters [[buffer(2)]],
    device uint *mediumStorage [[buffer(3)]], device atomic_uint *result [[buffer(4)]],
    device const uint *opticalOccurrences [[buffer(5)]],
    texture2d<float, access::read> source [[texture(0)]],
    texture2d<float, access::read> depth [[texture(1)]],
    texture2d<float, access::write> target [[texture(2)]], uint2 pixel [[thread_position_in_grid]]
) {
    if (pixel.x >= parameters.frame.x || pixel.y >= parameters.frame.y) return;
    float4 originalColor = source.read(pixel);
    float2 ndc = float2((float(pixel.x) + 0.5) * 2 / parameters.frame.x - 1,
                       1 - (float(pixel.y) + 0.5) * 2 / parameters.frame.y);
    float4 first = parameters.inverseProjection * float4(ndc, 0, 1);
    float4 second = parameters.inverseProjection * float4(ndc, 1, 1);
    float4 middle = parameters.inverseProjection * float4(ndc, 0.5, 1);
    if (middle.w == 0) { atomic_fetch_max_explicit(result, 3, memory_order_relaxed); return; }
    float3 middlePoint = middle.xyz / middle.w;
    float3 viewOrigin;
    if (first.w == 0) viewOrigin = second.xyz / second.w;
    else if (second.w == 0) viewOrigin = first.xyz / first.w;
    else {
        float3 a = first.xyz / first.w, b = second.xyz / second.w;
        viewOrigin = abs(a.z) < abs(b.z) ? a : b;
    }
    float3 origin = (parameters.worldFromView * float4(viewOrigin, 1)).xyz;
    float3 direction = normalize((parameters.worldFromView * float4(middlePoint - viewOrigin, 0)).xyz);
    if (!all(isfinite(origin)) || !all(isfinite(direction)) || !(dot(direction, direction) > 0)) {
        atomic_fetch_max_explicit(result, 3, memory_order_relaxed); return;
    }
    uint work = 0, failure = 0;
    RupaOpticalHit overlay = rupaOpticalVolumeTrace(origin, direction, triangles, nodes, parameters, opticalOccurrences, work, failure, UINT_MAX, UINT_MAX, true, 1);
    if (failure != 0) { atomic_fetch_max_explicit(result, failure, memory_order_relaxed); return; }
    if (overlay.triangle != UINT_MAX) { target.write(originalColor, pixel); return; }
    RupaOpticalHit hit = rupaOpticalVolumeTrace(origin, direction, triangles, nodes, parameters, opticalOccurrences, work, failure);
    if (failure != 0) { atomic_fetch_max_explicit(result, failure, memory_order_relaxed); return; }
    if (hit.triangle == UINT_MAX || triangles[hit.triangle].optics.y == 0 || triangles[hit.triangle].optics.z == 0) {
        target.write(originalColor, pixel); return;
    }
    ulong linear = ulong(pixel.y) * parameters.frame.x + pixel.x;
    device uint *media = mediumStorage + (parameters.limits.z <= 4 ? 0 : ulong(linear) * parameters.limits.z);
    uint localMedia[4];
    uint mediumCount = 0;
    // Original incidence, including a camera inside a volume: retain enclosing
    // occurrences in descending first-exit order, innermost last.
    bool insideRetainedHalfSpace = dot(parameters.section.xyz, origin) >= parameters.section.w;
    for (uint occurrenceIndex = 0; insideRetainedHalfSpace && occurrenceIndex < parameters.limits.z; ++occurrenceIndex) {
        if (!rupaOpticalConsumeWork(work, parameters, failure)) break;
        uint occurrence = opticalOccurrences[occurrenceIndex];
        RupaOpticalHit boundary = rupaOpticalVolumeTrace(origin, direction, triangles, nodes, parameters, opticalOccurrences, work, failure, UINT_MAX, occurrence, true);
        if (failure != 0) break;
        if (boundary.triangle == UINT_MAX) continue;
        RupaOpticalTriangle material = triangles[boundary.triangle];
        if (material.optics.y == 0 || material.optics.z == 0 || dot(direction, boundary.normal) <= 0) continue;
        if (mediumCount >= parameters.limits.z) { failure = 1; break; }
        uint position = mediumCount;
        while (position > 0) {
            if (!rupaOpticalConsumeWork(work, parameters, failure)) break;
            RupaOpticalHit earlier = rupaOpticalVolumeTrace(origin, direction, triangles, nodes, parameters, opticalOccurrences, work, failure, UINT_MAX, triangles[rupaMediumRead(localMedia, media, position - 1, parameters.limits.z)].identity.x, true);
            if (earlier.distance >= boundary.distance) break;
            rupaMediumWrite(localMedia, media, position, parameters.limits.z, rupaMediumRead(localMedia, media, position - 1, parameters.limits.z)); --position;
        }
        if (failure != 0) break;
        rupaMediumWrite(localMedia, media, position, parameters.limits.z, boundary.triangle); ++mediumCount;
    }
    float3 throughput = float3(1), radiance = float3(0);
    for (uint index = 0; index < mediumCount && failure == 0; ++index) {
        if (!rupaOpticalConsumeWork(work, parameters, failure)) break;
        uint owner = triangles[rupaMediumRead(localMedia, media, index, parameters.limits.z)].identity.x;
        RupaOpticalHit forward = rupaOpticalVolumeTrace(origin, direction, triangles, nodes,
            parameters, opticalOccurrences, work, failure, UINT_MAX, owner);
        RupaOpticalHit backward = rupaOpticalVolumeTrace(origin, -direction, triangles, nodes,
            parameters, opticalOccurrences, work, failure, UINT_MAX, owner);
        if (forward.triangle == UINT_MAX || backward.triangle == UINT_MAX) { failure = 2; break; }
        float total = forward.distance + backward.distance;
        if (!isfinite(total) || !(total > 0)) { failure = 3; break; }
        RupaOpticalTriangle material = triangles[forward.triangle];
        float metres = material.optics.z * (forward.distance / total)
            / max(abs(dot(direction, backward.normal)), FLT_MIN);
        throughput *= pow(material.baseColor.xyz, float3(metres));
    }
    float coverage = 0;
    bool finished = false;
    for (uint interaction = 0; interaction < parameters.limits.x && failure == 0; ++interaction) {
        if (hit.triangle == UINT_MAX) {
            // The same authored canvas value supplies known backdrop radiance.
            // Preserve partial-alpha composition without inventing an opaque sky.
            radiance += throughput * parameters.background.xyz * parameters.background.w;
            coverage += (1 - coverage) * parameters.background.w;
            finished = true; break;
        }
        RupaOpticalTriangle material = triangles[hit.triangle];
        float3 point = origin + direction * hit.distance;
        float4 reflected = material.optics.y > 0 && material.optics.z > 0
            ? float4(rupaOpticalStudio(material, hit.sectionCap ? hit.normal : material.shadingNormal.xyz, -direction, parameters), material.finish.y)
            : rupaOpticalHitColor(hit, point, direction, triangles, parameters, source, depth);
        if (material.optics.y == 0 || material.optics.z == 0) {
            radiance += throughput * reflected.xyz * reflected.w;
            coverage += max(throughput.x, max(throughput.y, throughput.z)) * reflected.w;
            throughput *= 1 - reflected.w;
            if (all(throughput == 0)) { finished = true; break; }
            origin = rupaOpticalAdvance(point, direction);
            hit = rupaOpticalVolumeTrace(origin, direction, triangles, nodes, parameters, opticalOccurrences, work, failure, hit.sectionCap ? UINT_MAX : hit.triangle);
            continue;
        }
        bool entering = dot(direction, hit.normal) < 0;
        float3 normal = entering ? hit.normal : -hit.normal;
        float sourceIOR = mediumCount == 0 ? 1 : triangles[rupaMediumRead(localMedia, media, mediumCount - 1, parameters.limits.z)].optics.x;
        float targetIOR = material.optics.x;
        uint removal = UINT_MAX;
        if (!entering) {
            for (uint index = 0; index < mediumCount; ++index) {
                if (!rupaOpticalConsumeWork(work, parameters, failure)) break;
                if (triangles[rupaMediumRead(localMedia, media, index, parameters.limits.z)].identity.x == material.identity.x) { removal = index; break; }
            }
            if (failure != 0) break;
            if (removal == UINT_MAX) { failure = 2; break; }
            targetIOR = removal + 1 < mediumCount ? sourceIOR : (removal == 0 ? 1 : triangles[rupaMediumRead(localMedia, media, removal - 1, parameters.limits.z)].optics.x);
        }
        float ratio = sourceIOR / targetIOR;
        float cosine = saturate(-dot(direction, normal));
        float discriminant = 1 - ratio * ratio * (1 - cosine * cosine);
        if (discriminant < 0) {
            direction = reflect(direction, normal);
        } else {
            float eta = (sourceIOR - targetIOR) / (sourceIOR + targetIOR);
            float fresnel = eta * eta + (1 - eta * eta) * pow(1 - cosine, 5.0);
            float transmissionWeight = material.optics.y * (1 - material.optics.w) * (1 - fresnel);
            radiance += throughput * reflected.xyz * (1 - transmissionWeight) * reflected.w;
            coverage += max(throughput.x, max(throughput.y, throughput.z)) * (1 - transmissionWeight) * reflected.w;
            throughput *= transmissionWeight;
            direction = normalize(ratio * direction + (ratio * cosine - sqrt(discriminant)) * normal);
            if (entering) {
                if (mediumCount >= parameters.limits.z) { failure = 1; break; }
                rupaMediumWrite(localMedia, media, mediumCount++, parameters.limits.z, hit.triangle);
                // Authored metre thickness owns optical path length; it is never
                // a nanometre thin-film phase or the mesh's arbitrary UV scale.
                float opticalMetres = material.optics.z / max(abs(dot(direction, normal)), FLT_MIN);
                throughput *= pow(material.baseColor.xyz, float3(opticalMetres));
            } else {
                for (uint index = removal; index + 1 < mediumCount; ++index) {
                    if (!rupaOpticalConsumeWork(work, parameters, failure)) break;
                    rupaMediumWrite(localMedia, media, index, parameters.limits.z,
                        rupaMediumRead(localMedia, media, index + 1, parameters.limits.z));
                }
                if (failure != 0) break;
                --mediumCount;
            }
        }
        if (!all(isfinite(direction)) || !all(isfinite(throughput)) || !all(isfinite(radiance))) { failure = 3; break; }
        if (all(throughput == 0)) { finished = true; break; }
        origin = rupaOpticalAdvance(point, direction);
        hit = rupaOpticalVolumeTrace(origin, direction, triangles, nodes, parameters, opticalOccurrences, work, failure, hit.sectionCap ? UINT_MAX : hit.triangle);
    }
    if (!finished && failure == 0) failure = 1;
    if (!all(isfinite(radiance)) || !all(isfinite(throughput)) || !isfinite(coverage)) failure = 3;
    if (failure != 0) { atomic_fetch_max_explicit(result, failure, memory_order_relaxed); return; }
    // Premultiplied alpha keeps an unobstructed original ray miss transparent;
    // the existing canvas owner composes its theme/custom background afterward.
    target.write(float4(radiance, saturate(coverage)), pixel);
}

kernel void rupaOpticalVolumePublish(
    device atomic_uint *result [[buffer(0)]], constant uint &hasPrevious [[buffer(1)]],
    texture2d<float, access::read> candidate [[texture(0)]],
    texture2d<float, access::read> previous [[texture(1)]],
    texture2d<float, access::write> target [[texture(2)]], uint2 pixel [[thread_position_in_grid]]
) {
    if (pixel.x >= target.get_width() || pixel.y >= target.get_height()) return;
    if (atomic_load_explicit(result, memory_order_relaxed) == 0) target.write(candidate.read(pixel), pixel);
    else if (hasPrevious != 0 && pixel.x < previous.get_width() && pixel.y < previous.get_height()) target.write(previous.read(pixel), pixel);
    else if (pixel.x < previous.get_width() && pixel.y < previous.get_height()) target.write(previous.read(pixel), pixel);
    else target.write(float4(0), pixel);
}
