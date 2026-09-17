import SwiftUI
import RupaCore

struct WorkspaceObjectTransformInspectorView: View {
    var nodes: [SceneNode]
    var displayUnit: LengthDisplayUnit
    var positionSliderMetersRange: ClosedRange<Double>
    var materialOptions: [WorkspaceObjectMaterialOption]
    var onCommitProperties: ([EditorCommand], String) -> Void
    var isBusy: Bool
    var hasMatchingPreview: Bool
    var previewError: String?
    var onDraftChanged: () -> Void
    var onPreview: ([EditorCommand]) -> Void
    var onApply: () -> Void
    var onCancel: () -> Void
    @State private var transforms: [SceneNodeID: Transform3D] = [:]
    @State private var transformError: String?

    private var draftNodes: [SceneNode] {
        nodes.map { node in
            var draft = node
            if let transform = transforms[node.id] { draft.localTransform = transform }
            return draft
        }
    }

    var body: some View {
        stateSection
        switch Result(catching: { try draftNodes.map { try WorkspaceTransformMatrix.components(of: $0.localTransform) } }) {
        case .success(let components):
            positionSection
            rotationSection(components)
            scaleSection(components)
            if components.contains(where: { abs($0.shear.x) + abs($0.shear.y) + abs($0.shear.z) > 1.0e-12 }) {
                inspectorSection("Retained Shear (XY, XZ, YZ)") {
                    ForEach(Array(components.enumerated()), id: \.offset) { _, component in
                        Text("\(component.shear.x), \(component.shear.y), \(component.shear.z)")
                            .font(.caption.monospacedDigit())
                    }
                }
            }
        case .failure(let error):
            Text(error.localizedDescription).font(.callout).foregroundStyle(.red)
                .accessibilityIdentifier("WorkspaceObjectTransform.componentsError")
        }
        materialSection
        transformSection
            .onChange(of: nodes) { _, _ in transforms.removeAll(); transformError = nil }
        if let error = transformError ?? previewError {
            Text(error).foregroundStyle(.red).font(.callout)
                .accessibilityIdentifier("WorkspaceObjectTransform.error")
        }
        if !transforms.isEmpty {
            inspectorActionRow {
                Button("Cancel") { transforms.removeAll(); transformError = nil; onCancel() }
                Button("Preview") {
                    onPreview(nodes.compactMap { node in transforms[node.id].map { .setSceneNodeTransform(id: node.id, localTransform: $0) } })
                }.disabled(isBusy)
                Button("Apply", action: onApply).disabled(isBusy || !hasMatchingPreview)
            }
        }
    }

    private func onSetTransformComponent(_ component: InspectorTransformComponent, _ value: Double) {
        guard !isBusy else { return }
        do {
            var next = transforms
            for node in draftNodes {
                guard !node.isLocked else { throw EditorError(code: .commandInvalid, message: "Unlock selected objects before changing their transforms.") }
                next[node.id] = try WorkspaceTransformMatrix.replacing(component, with: value, in: node.localTransform)
            }
            transforms = next
            transformError = nil
            onDraftChanged()
        } catch {
            transformError = WorkspaceFailureLog.shared.record(error)
        }
    }

    private var stateSection: some View {
        inspectorSection("State") {
            boolChoicePicker(
                "Visible",
                nodes: nodes,
                keyPath: \.isVisible,
                command: { .setSceneNodeVisibility(id: $0, isVisible: $1) }
            )

            boolChoicePicker(
                "Locked",
                nodes: nodes,
                keyPath: \.isLocked,
                command: { .setSceneNodeLock(id: $0, isLocked: $1) }
            )
        }
    }

    private var positionSection: some View {
        inspectorSection("Position") {
            workspaceLengthControl(
                "X",
                values: draftNodes.map { WorkspaceTransformMatrix.translation(for: $0).x },
                displayUnit: displayUnit,
                sliderMetersRange: positionSliderMetersRange
            ) { meters in
                onSetTransformComponent(.translationX, meters)
            }
            workspaceLengthControl(
                "Y",
                values: draftNodes.map { WorkspaceTransformMatrix.translation(for: $0).y },
                displayUnit: displayUnit,
                sliderMetersRange: positionSliderMetersRange
            ) { meters in
                onSetTransformComponent(.translationY, meters)
            }
            workspaceLengthControl(
                "Z",
                values: draftNodes.map { WorkspaceTransformMatrix.translation(for: $0).z },
                displayUnit: displayUnit,
                sliderMetersRange: positionSliderMetersRange
            ) { meters in
                onSetTransformComponent(.translationZ, meters)
            }
        }
    }

    private func rotationSection(_ components: [WorkspaceTransformMatrix.Components]) -> some View {
        inspectorSection("Rotation (X → Y → Z)") {
            numericControl("X", values: components.map { $0.rotationDegrees.x }, sliderRange: -180...180, onChange: { onSetTransformComponent(.rotationX, $0) }, unitLabel: { "°" })
            numericControl("Y", values: components.map { $0.rotationDegrees.y }, sliderRange: -180...180, onChange: { onSetTransformComponent(.rotationY, $0) }, unitLabel: { "°" })
            numericControl("Z", values: components.map { $0.rotationDegrees.z }, sliderRange: -180...180, onChange: { onSetTransformComponent(.rotationZ, $0) }, unitLabel: { "°" })
        }
    }

    private func scaleSection(_ components: [WorkspaceTransformMatrix.Components]) -> some View {
        inspectorSection("Transform Scale") {
            workspaceScaleFactorControl(
                "X",
                values: components.map { $0.scale.x }
            ) { value in
                onSetTransformComponent(.scaleX, value)
            }
            workspaceScaleFactorControl(
                "Y",
                values: components.map { $0.scale.y }
            ) { value in
                onSetTransformComponent(.scaleY, value)
            }
            workspaceScaleFactorControl(
                "Z",
                values: components.map { $0.scale.z }
            ) { value in
                onSetTransformComponent(.scaleZ, value)
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
                selection: materialBinding
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
            .disabled(isBusy)
            .accessibilityIdentifier("WorkspaceObjectTransform.material")
        }
    }

    var materialBinding: Binding<InspectorMaterialChoice> {
        Binding(
            get: { materialChoice(for: nodes) },
            set: { choice in
                guard !isBusy else { return }
                switch choice {
                case .mixed: return
                case .none:
                    onCommitProperties(nodes.map { .setSceneNodeMaterial(id: $0.id, materialID: nil) }, "Change Object Materials")
                case .material(let materialID):
                    onCommitProperties(nodes.map { .setSceneNodeMaterial(id: $0.id, materialID: materialID) }, "Change Object Materials")
                }
            }
        )
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
                    transforms = Dictionary(uniqueKeysWithValues: nodes.map { ($0.id, Transform3D.identity) })
                    onDraftChanged()
                }
                .disabled(isBusy || nodes.contains(where: \.isLocked) || nodes.allSatisfy { $0.localTransform.matrix == .identity })
            }
        }
    }

    private func boolChoicePicker(
        _ title: String,
        nodes: [SceneNode],
        keyPath: KeyPath<SceneNode, Bool>,
        command: @escaping (SceneNodeID, Bool) -> EditorCommand
    ) -> some View {
        inspectorControlRow(title) {
            Picker(
                "",
                selection: boolBinding(title, keyPath: keyPath, command: command)
            ) {
                ForEach(InspectorBoolChoice.allCases) { choice in
                    Text(choice.rawValue)
                        .tag(choice)
                }
            }
            .labelsHidden()
            .controlSize(.small)
            .frame(width: inspectorControlWidth)
            .disabled(isBusy)
            .accessibilityIdentifier("WorkspaceObjectTransform.\(title)")
        }
    }

    func boolBinding(_ title: String, keyPath: KeyPath<SceneNode, Bool>,
                     command: @escaping (SceneNodeID, Bool) -> EditorCommand) -> Binding<InspectorBoolChoice> {
        Binding(
            get: { boolChoice(nodes: nodes, keyPath: keyPath) },
            set: { choice in
                guard !isBusy else { return }
                switch choice {
                case .mixed: return
                case .on:
                    onCommitProperties(nodes.map { command($0.id, true) }, "Change Object \(title)")
                case .off:
                    onCommitProperties(nodes.map { command($0.id, false) }, "Change Object \(title)")
                }
            }
        )
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
