import SwiftUI
import RupaCore

struct WorkspaceObjectTransformInspectorView: View {
    var nodes: [SceneNode]
    var displayUnit: LengthDisplayUnit
    var positionSliderRange: ClosedRange<Double>
    var materialOptions: [WorkspaceObjectMaterialOption]
    var onSetVisibility: (SceneNodeID, Bool) -> Void
    var onSetLock: (SceneNodeID, Bool) -> Void
    var onSetTransformComponent: (InspectorTransformComponent, Double) -> Void
    var onSetMaterial: (SceneNodeID, MaterialID?) -> Void
    var onResetTransform: () -> Void

    var body: some View {
        stateSection
        positionSection
        scaleSection
        materialSection
        transformSection
    }

    private var stateSection: some View {
        inspectorSection("State") {
            boolChoicePicker(
                "Visible",
                nodes: nodes,
                keyPath: \.isVisible,
                apply: onSetVisibility
            )

            boolChoicePicker(
                "Locked",
                nodes: nodes,
                keyPath: \.isLocked,
                apply: onSetLock
            )
        }
    }

    private var positionSection: some View {
        inspectorSection("Position") {
            workspaceLengthControl(
                "X",
                values: nodes.map { WorkspaceTransformMatrix.translation(for: $0).x },
                displayUnit: displayUnit,
                sliderRange: positionSliderRange
            ) { meters in
                onSetTransformComponent(.translationX, meters)
            }
            workspaceLengthControl(
                "Y",
                values: nodes.map { WorkspaceTransformMatrix.translation(for: $0).y },
                displayUnit: displayUnit,
                sliderRange: positionSliderRange
            ) { meters in
                onSetTransformComponent(.translationY, meters)
            }
            workspaceLengthControl(
                "Z",
                values: nodes.map { WorkspaceTransformMatrix.translation(for: $0).z },
                displayUnit: displayUnit,
                sliderRange: positionSliderRange
            ) { meters in
                onSetTransformComponent(.translationZ, meters)
            }
        }
    }

    private var scaleSection: some View {
        inspectorSection("Transform Scale") {
            numericControl(
                "X",
                values: nodes.map { WorkspaceTransformMatrix.scale(for: $0).x },
                sliderRange: 0.01 ... 10.0
            ) { value in
                onSetTransformComponent(.scaleX, max(value, 0.0001))
            }
            numericControl(
                "Y",
                values: nodes.map { WorkspaceTransformMatrix.scale(for: $0).y },
                sliderRange: 0.01 ... 10.0
            ) { value in
                onSetTransformComponent(.scaleY, max(value, 0.0001))
            }
            numericControl(
                "Z",
                values: nodes.map { WorkspaceTransformMatrix.scale(for: $0).z },
                sliderRange: 0.01 ... 10.0
            ) { value in
                onSetTransformComponent(.scaleZ, max(value, 0.0001))
            }
        }
    }

    private var materialSection: some View {
        inspectorSection("Material") {
            if materialOptions.isEmpty {
                workspaceInspectorValueRow("Material", "No Materials")
            } else {
                materialPicker
            }
        }
    }

    private var materialPicker: some View {
        inspectorControlRow("Material") {
            Picker(
                "",
                selection: Binding(
                    get: {
                        materialChoice(for: nodes)
                    },
                    set: { choice in
                        switch choice {
                        case .mixed:
                            return
                        case .none:
                            for node in nodes {
                                onSetMaterial(node.id, nil)
                            }
                        case .material(let materialID):
                            for node in nodes {
                                onSetMaterial(node.id, materialID)
                            }
                        }
                    }
                )
            ) {
                if materialChoice(for: nodes) == .mixed {
                    Text("Mixed").tag(InspectorMaterialChoice.mixed)
                }
                Text("None").tag(InspectorMaterialChoice.none)
                ForEach(materialOptions) { material in
                    Text(material.name)
                        .tag(InspectorMaterialChoice.material(material.id))
                }
            }
            .labelsHidden()
            .controlSize(.small)
            .frame(minWidth: inspectorControlWidth)
        }
    }

    private var transformSection: some View {
        inspectorSection("Transform") {
            workspaceInspectorValueRow("Local", WorkspaceTransformMatrix.transformSummary(for: nodes))
            workspaceInspectorValueRow(
                "Custom",
                "\(nodes.filter { $0.localTransform.matrix != .identity }.count)"
            )
            if nodes.count == 1, let node = nodes.first {
                let rows = Array(WorkspaceTransformMatrix.matrixRows(node.localTransform.matrix.values).enumerated())
                ForEach(rows, id: \.offset) { _, row in
                    workspaceInspectorValueRow(row.title, row.value)
                }
            }

            inspectorActionRow {
                Button("Reset Transform") {
                    onResetTransform()
                }
                .disabled(nodes.allSatisfy { $0.localTransform.matrix == .identity })
            }
        }
    }

    private func boolChoicePicker(
        _ title: String,
        nodes: [SceneNode],
        keyPath: KeyPath<SceneNode, Bool>,
        apply: @escaping (SceneNodeID, Bool) -> Void
    ) -> some View {
        inspectorControlRow(title) {
            Picker(
                "",
                selection: Binding(
                    get: {
                        boolChoice(nodes: nodes, keyPath: keyPath)
                    },
                    set: { choice in
                        switch choice {
                        case .mixed:
                            return
                        case .on:
                            for node in nodes {
                                apply(node.id, true)
                            }
                        case .off:
                            for node in nodes {
                                apply(node.id, false)
                            }
                        }
                    }
                )
            ) {
                ForEach(InspectorBoolChoice.allCases) { choice in
                    Text(choice.rawValue)
                        .tag(choice)
                }
            }
            .labelsHidden()
            .controlSize(.small)
            .frame(width: inspectorControlWidth)
        }
    }

    private func boolChoice(
        nodes: [SceneNode],
        keyPath: KeyPath<SceneNode, Bool>
    ) -> InspectorBoolChoice {
        guard let first = nodes.first?[keyPath: keyPath],
              nodes.allSatisfy({ $0[keyPath: keyPath] == first }) else {
            return .mixed
        }
        return first ? .on : .off
    }

    private func materialChoice(for nodes: [SceneNode]) -> InspectorMaterialChoice {
        guard let first = nodes.first?.materialID else {
            if nodes.allSatisfy({ $0.materialID == nil }) {
                return .none
            }
            return .mixed
        }
        guard nodes.allSatisfy({ $0.materialID == first }) else {
            return .mixed
        }
        return .material(first)
    }

}
