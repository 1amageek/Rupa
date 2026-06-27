import Foundation
import RupaCore

enum WorkspaceTransformMatrix {
    static func normalizedValues(_ values: [Double]) -> [Double] {
        guard values.count == 16 else {
            return Matrix4x4.identity.values
        }
        return values
    }

    static func translation(for node: SceneNode) -> InspectorVector3D {
        let values = normalizedValues(node.localTransform.matrix.values)
        return InspectorVector3D(x: values[12], y: values[13], z: values[14])
    }

    static func scale(for node: SceneNode) -> InspectorVector3D {
        let values = normalizedValues(node.localTransform.matrix.values)
        return InspectorVector3D(x: values[0], y: values[5], z: values[10])
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
