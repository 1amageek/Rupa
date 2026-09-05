import Foundation
import RupaCore

enum WorkspaceTransformMatrix {
    struct Components {
        var translation: InspectorVector3D
        var rotationDegrees: InspectorVector3D
        var scale: InspectorVector3D
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
        var sx = hypot(hypot(m[0], m[4]), m[8])
        let sy = hypot(hypot(m[1], m[5]), m[9])
        let sz = hypot(hypot(m[2], m[6]), m[10])
        guard sx.isFinite, sy.isFinite, sz.isFinite, min(sx, sy, sz) > 1.0e-12 else {
            throw invalid("The transform has a zero or non-finite scale.")
        }
        let determinant = m[0] * (m[5] * m[10] - m[6] * m[9])
            - m[1] * (m[4] * m[10] - m[6] * m[8])
            + m[2] * (m[4] * m[9] - m[5] * m[8])
        if determinant < 0 { sx = -sx }
        let r = [m[0] / sx, m[1] / sy, m[2] / sz,
                 m[4] / sx, m[5] / sy, m[6] / sz,
                 m[8] / sx, m[9] / sy, m[10] / sz]
        let xy = r[0] * r[1] + r[3] * r[4] + r[6] * r[7]
        let xz = r[0] * r[2] + r[3] * r[5] + r[6] * r[8]
        let yz = r[1] * r[2] + r[4] * r[5] + r[7] * r[8]
        guard max(abs(xy), abs(xz), abs(yz)) < 1.0e-9 else {
            throw invalid("The transform contains shear. TRS editing cannot preserve this placement.")
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
            scale: InspectorVector3D(x: sx, y: sy, z: sz)
        )
    }

    static func transform(from components: Components) throws -> Transform3D {
        let t = components.translation
        let a = components.rotationDegrees
        let s = components.scale
        guard [t.x, t.y, t.z, a.x, a.y, a.z, s.x, s.y, s.z].allSatisfy(\.isFinite),
              min(abs(s.x), abs(s.y), abs(s.z)) > 1.0e-12 else {
            throw invalid("Placement requires finite values and non-zero scales.")
        }
        let x = a.x * .pi / 180, y = a.y * .pi / 180, z = a.z * .pi / 180
        let cx = cos(x), sx = sin(x), cy = cos(y), sy = sin(y), cz = cos(z), sz = sin(z)
        return Transform3D(matrix: try Matrix4x4(values: [
            cz * cy * s.x, (cz * sy * sx - sz * cx) * s.y, (cz * sy * cx + sz * sx) * s.z, t.x,
            sz * cy * s.x, (sz * sy * sx + cz * cx) * s.y, (sz * sy * cx - cz * sx) * s.z, t.y,
            -sy * s.x, cy * sx * s.y, cy * cx * s.z, t.z,
            0, 0, 0, 1,
        ]))
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
