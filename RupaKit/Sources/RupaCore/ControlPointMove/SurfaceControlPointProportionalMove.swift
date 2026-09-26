import SwiftCAD
import RupaCoreTypes

/// The displacement of every control point of one B-spline surface under a proportional,
/// optionally mirrored, control point move.
struct SurfaceControlPointProportionalMove: Sendable {
    /// A control point's place in the net: `u` indexes a row, `v` the rows.
    struct NetIndex: Hashable, Sendable {
        var u: Int
        var v: Int
    }

    /// A mirror plane in the surface's own coordinates.
    struct MirrorPlane: Sendable {
        var origin: Point3D
        var normal: Vector3D
    }

    let options: SurfaceControlPointMoveOptions
    let distanceTolerance: Double

    /// The displacement of each control point that moves, for `selected` (in selection order, the
    /// last one active) moved by `delta`.
    func displacements(
        controlPoints: [[Point3D]],
        selected: [NetIndex],
        delta: Vector3D,
        mirror: MirrorPlane?
    ) throws -> [NetIndex: Vector3D] {
        guard !selected.isEmpty else {
            throw EditorError(code: .commandInvalid, message: "A control point move needs a selected control point.")
        }
        for index in selected {
            guard controlPoints.indices.contains(index.v), controlPoints[index.v].indices.contains(index.u) else {
                throw EditorError(code: .referenceUnresolved, message: "A control point move references a missing control point.")
            }
        }
        if options.proportional != .none {
            for falloff in [options.falloffU, options.falloffV] {
                guard falloff.isFinite, falloff > 0 else {
                    throw EditorError(code: .commandInvalid, message: "A proportional falloff must be a positive finite number of control points.")
                }
            }
        }
        let direct = weights(seeds: selected, in: controlPoints)
        guard let mirror else {
            return direct.mapValues { delta * $0 }
        }
        let normal = try mirror.normal.normalized(tolerance: distanceTolerance)
        let mirroredSeeds = try selected.map { try counterpart(of: $0, in: controlPoints, origin: mirror.origin, normal: normal) }
        let mirrored = weights(seeds: mirroredSeeds, in: controlPoints)
        let reflected = delta - normal * (2 * delta.dot(normal))
        var result: [NetIndex: Vector3D] = [:]
        for index in Set(direct.keys).union(mirrored.keys) {
            let w = direct[index] ?? 0
            let m = mirrored[index] ?? 0
            if w > m {
                result[index] = delta * w
            } else if m > w {
                result[index] = reflected * m
            } else if w > 0 {
                // Both sides reach the point equally, as a point on the plane does from itself:
                // the mean of the two moves keeps it on the plane.
                result[index] = (delta + reflected) * (w / 2)
            }
        }
        return result
    }

    /// The weight of every control point that moves, from `seeds` (the last one active).
    private func weights(seeds: [NetIndex], in controlPoints: [[Point3D]]) -> [NetIndex: Double] {
        var result: [NetIndex: Double] = [:]
        switch options.proportional {
        case .none:
            for seed in seeds { result[seed] = 1 }
        case .selected:
            let active = seeds[seeds.count - 1]
            for seed in seeds {
                let w = falloff(from: active, to: seed)
                if w > 0 { result[seed] = max(result[seed] ?? 0, w) }
            }
        case .all:
            for v in controlPoints.indices {
                for u in controlPoints[v].indices {
                    let index = NetIndex(u: u, v: v)
                    let w = seeds.map { falloff(from: $0, to: index) }.max() ?? 0
                    if w > 0 { result[index] = w }
                }
            }
        }
        return result
    }

    /// (1 − r²)² inside the falloff reach, where r is the hull distance in falloff units.
    private func falloff(from seed: NetIndex, to index: NetIndex) -> Double {
        let du = Double(abs(index.u - seed.u)) / options.falloffU
        let dv = Double(abs(index.v - seed.v)) / options.falloffV
        let r2 = du * du + dv * dv
        guard r2 < 1 else { return 0 }
        return (1 - r2) * (1 - r2)
    }

    /// The control point at `index`'s reflection across the plane.
    private func counterpart(
        of index: NetIndex,
        in controlPoints: [[Point3D]],
        origin: Point3D,
        normal: Vector3D
    ) throws -> NetIndex {
        let point = controlPoints[index.v][index.u]
        let reflection = point + normal * (-2 * (point - origin).dot(normal))
        var best: (NetIndex, Double)?
        for v in controlPoints.indices {
            for u in controlPoints[v].indices {
                let distance = (controlPoints[v][u] - reflection).length
                if distance <= distanceTolerance, distance < (best?.1 ?? .infinity) {
                    best = (NetIndex(u: u, v: v), distance)
                }
            }
        }
        guard let best else {
            throw EditorError(
                code: .commandInvalid,
                message: "A mirrored control point move needs a control point at the mirror image of control point (\(index.u), \(index.v))."
            )
        }
        return best.0
    }
}
