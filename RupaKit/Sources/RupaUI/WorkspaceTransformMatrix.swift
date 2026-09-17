import Foundation
import RupaCore
import simd

enum WorkspaceTransformMatrix {
    struct Components {
        var translation: InspectorVector3D
        var rotationDegrees: InspectorVector3D
        var scale: InspectorVector3D
        var shear: InspectorVector3D = .init(x: 0, y: 0, z: 0)
    }

    static func translation(for node: SceneNode) -> InspectorVector3D {
        let values = node.localTransform.matrix.values
        return InspectorVector3D(x: values[3], y: values[7], z: values[11])
    }

    static func components(of transform: Transform3D) throws -> Components {
        try transform.validate()
        let m = transform.matrix.values
        guard m[12] == 0, m[13] == 0, m[14] == 0, m[15] == 1 else {
            throw invalid("The transform contains perspective. TRS editing requires an affine placement.")
        }
        // QR factors the linear part into a proper rotation and H * S.
        // Retain the upper-triangular shear instead of projecting onto TRS.
        let a = SIMD3(m[0], m[4], m[8])
        let b = SIMD3(m[1], m[5], m[9])
        let c = SIMD3(m[2], m[6], m[10])
        var sx = hypot(hypot(a.x, a.y), a.z)
        guard sx.isFinite, sx > 1.0e-12 else {
            throw invalid("The transform has a zero or non-finite scale.")
        }
        var q0 = a / sx
        var r01 = simd_dot(q0, b)
        let residualB = b - q0 * r01
        let sy = hypot(hypot(residualB.x, residualB.y), residualB.z)
        guard sy.isFinite, sy > 1.0e-12 else {
            throw invalid("The transform has a singular or non-finite basis.")
        }
        let q1 = residualB / sy
        var r02 = simd_dot(q0, c)
        let residualC = c - q0 * r02
        let r12 = simd_dot(q1, residualC)
        let orthogonalC = residualC - q1 * r12
        let sz = hypot(hypot(orthogonalC.x, orthogonalC.y), orthogonalC.z)
        guard sx.isFinite, sy.isFinite, sz.isFinite, min(sx, sy, sz) > 1.0e-12 else {
            throw invalid("The transform has a zero or non-finite scale.")
        }
        let q2 = orthogonalC / sz
        if simd_dot(q0, simd_cross(q1, q2)) < 0 {
            sx = -sx; q0 = -q0; r01 = -r01; r02 = -r02
        }
        let r = [q0.x, q1.x, q2.x, q0.y, q1.y, q2.y, q0.z, q1.z, q2.z]
        let xy = r[0] * r[1] + r[3] * r[4] + r[6] * r[7]
        let xz = r[0] * r[2] + r[3] * r[5] + r[6] * r[8]
        let yz = r[1] * r[2] + r[4] * r[5] + r[7] * r[8]
        guard max(abs(xy), abs(xz), abs(yz)) < 1.0e-9 else {
            throw invalid("The transform is too ill-conditioned for stable affine editing.")
        }
        let y = asin(min(1, max(-1, -r[6])))
        let x: Double
        let z: Double
        if abs(cos(y)) > 1.0e-9 {
            x = atan2(r[7], r[8])
            z = atan2(r[3], r[0])
        } else {
            x = atan2(-r[5], r[4])
            z = 0
        }
        return Components(
            translation: InspectorVector3D(x: m[3], y: m[7], z: m[11]),
            rotationDegrees: InspectorVector3D(x: x * 180 / .pi, y: y * 180 / .pi, z: z * 180 / .pi),
            scale: InspectorVector3D(x: sx, y: sy, z: sz),
            shear: InspectorVector3D(x: r01 / sy, y: r02 / sz, z: r12 / sz)
        )
    }

    static func transform(from components: Components) throws -> Transform3D {
        let t = components.translation
        let a = components.rotationDegrees
        let s = components.scale
        let h = components.shear
        guard [t.x, t.y, t.z, a.x, a.y, a.z, s.x, s.y, s.z, h.x, h.y, h.z].allSatisfy(\.isFinite),
              min(abs(s.x), abs(s.y), abs(s.z)) > 1.0e-12 else {
            throw invalid("Placement requires finite values and non-zero scales.")
        }
        let x = a.x * .pi / 180, y = a.y * .pi / 180, z = a.z * .pi / 180
        let cx = cos(x), sx = sin(x), cy = cos(y), sy = sin(y), cz = cos(z), sz = sin(z)
        let q0 = SIMD3(cz * cy, sz * cy, -sy)
        let q1 = SIMD3(cz * sy * sx - sz * cx, sz * sy * sx + cz * cx, cy * sx)
        let q2 = SIMD3(cz * sy * cx + sz * sx, sz * sy * cx - cz * sx, cy * cx)
        let c0 = q0 * s.x
        let c1 = (q0 * h.x + q1) * s.y
        let c2 = (q0 * h.y + q1 * h.z + q2) * s.z
        let result = Transform3D(matrix: try Matrix4x4(values: [
            c0.x, c1.x, c2.x, t.x,
            c0.y, c1.y, c2.y, t.y,
            c0.z, c1.z, c2.z, t.z,
            0, 0, 0, 1,
        ]))
        try result.validate()
        return result
    }

    static func replacing(_ component: InspectorTransformComponent, with value: Double, in transform: Transform3D) throws -> Transform3D {
        var c = try components(of: transform)
        switch component {
        case .translationX: c.translation.x = value
        case .translationY: c.translation.y = value
        case .translationZ: c.translation.z = value
        case .rotationX: c.rotationDegrees.x = value
        case .rotationY: c.rotationDegrees.y = value
        case .rotationZ: c.rotationDegrees.z = value
        case .scaleX: c.scale.x = value
        case .scaleY: c.scale.y = value
        case .scaleZ: c.scale.z = value
        }
        return try self.transform(from: c)
    }

    private static func invalid(_ message: String) -> EditorError {
        EditorError(code: .commandInvalid, message: message)
    }

    static func transformSummary(for nodes: [SceneNode]) -> String {
        let identityCount = nodes.filter { $0.localTransform.matrix == .identity }.count
        if identityCount == nodes.count {
            return "Identity"
        }
        if identityCount == 0 {
            return nodes.count == 1 ? "Custom Matrix" : "Custom Matrices"
        }
        return "Mixed"
    }

    static func matrixRows(_ values: [Double]) -> [WorkspaceInspectorTextRow] {
        guard values.count == 16 else {
            return [WorkspaceInspectorTextRow(title: "Matrix", value: "Invalid")]
        }
        return [
            WorkspaceInspectorTextRow(title: "M1", value: matrixRow(values, row: 0)),
            WorkspaceInspectorTextRow(title: "M2", value: matrixRow(values, row: 1)),
            WorkspaceInspectorTextRow(title: "M3", value: matrixRow(values, row: 2)),
            WorkspaceInspectorTextRow(title: "M4", value: matrixRow(values, row: 3)),
        ]
    }

    private static func matrixRow(_ values: [Double], row: Int) -> String {
        let offset = row * 4
        return values[offset ..< offset + 4]
            .map { formattedMatrixValue($0) }
            .joined(separator: "  ")
    }

    private static func formattedMatrixValue(_ value: Double) -> String {
        value.formatted(.number.precision(.fractionLength(0...3)))
    }
}
