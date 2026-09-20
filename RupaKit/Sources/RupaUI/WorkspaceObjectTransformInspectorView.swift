import SwiftUI
import RupaCore

struct WorkspaceObjectTransformInspectorView: View {
    @Environment(\.self) private var environment
    var nodes: [SceneNode]
    var displayUnit: LengthDisplayUnit
    var positionSliderMetersRange: ClosedRange<Double>
    var materialOptions: [WorkspaceObjectMaterialOption]
    /// The appearance each selected node authors, keyed by node.
    ///
    /// A node missing from this map has no appearance a person can author, so
    /// the section offers no control for it. See `RupaCore/DESIGN.md`.
    var appearances: [SceneNodeID: RupaCore.Material]
    var onCommitProperties: ([EditorCommand], String) -> Void
    var isBusy: Bool
    var onEditTransform: (InspectorTransformComponent, Double) -> Void

    var body: some View {
        switch Result(catching: { try nodes.map { try WorkspaceTransformMatrix.components(of: $0.localTransform) } }) {
        case .success(let components):
            inspectorSection("Transform") {
                positionSection
                scaleSection(components)
                rotationSection(components)
            }
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
        stateSection
        DisclosureGroup("Material") { materialSection }
        DisclosureGroup("Transform Details") { transformSection }
    }

    func onSetTransformComponent(_ component: InspectorTransformComponent, _ value: Double) {
        guard !isBusy else { return }
        onEditTransform(component, value)
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
        InspectorVectorRow(title: "Position") {
            workspaceLengthControl(
                "X",
                values: nodes.map { WorkspaceTransformMatrix.translation(for: $0).x },
                displayUnit: displayUnit,
                sliderMetersRange: positionSliderMetersRange, axisField: true
            ) { meters in
                onSetTransformComponent(.translationX, meters)
            }
            workspaceLengthControl(
                "Y",
                values: nodes.map { WorkspaceTransformMatrix.translation(for: $0).y },
                displayUnit: displayUnit,
                sliderMetersRange: positionSliderMetersRange, axisField: true
            ) { meters in
                onSetTransformComponent(.translationY, meters)
            }
            workspaceLengthControl(
                "Z",
                values: nodes.map { WorkspaceTransformMatrix.translation(for: $0).z },
                displayUnit: displayUnit,
                sliderMetersRange: positionSliderMetersRange, axisField: true
            ) { meters in
                onSetTransformComponent(.translationZ, meters)
            }
        }
    }

    private func rotationSection(_ components: [WorkspaceTransformMatrix.Components]) -> some View {
        InspectorVectorRow(title: "Rotation") {
            numericControl("X", values: components.map { $0.rotationDegrees.x }, sliderRange: -180...180, axisField: true, onChange: { onSetTransformComponent(.rotationX, $0) }, unitLabel: { "°" })
            numericControl("Y", values: components.map { $0.rotationDegrees.y }, sliderRange: -180...180, axisField: true, onChange: { onSetTransformComponent(.rotationY, $0) }, unitLabel: { "°" })
            numericControl("Z", values: components.map { $0.rotationDegrees.z }, sliderRange: -180...180, axisField: true, onChange: { onSetTransformComponent(.rotationZ, $0) }, unitLabel: { "°" })
        }
    }

    private func scaleSection(_ components: [WorkspaceTransformMatrix.Components]) -> some View {
        InspectorVectorRow(title: "Scale") {
            workspaceScaleFactorControl(
                "X",
                values: components.map { $0.scale.x }, axisField: true
            ) { value in
                onSetTransformComponent(.scaleX, value)
            }
            workspaceScaleFactorControl(
                "Y",
                values: components.map { $0.scale.y }, axisField: true
            ) { value in
                onSetTransformComponent(.scaleY, value)
            }
            workspaceScaleFactorControl(
                "Z",
                values: components.map { $0.scale.z }, axisField: true
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
            appearanceControls
        }
    }

    /// The four components `Material` declares, for a selection whose every node
    /// answers with an appearance the command accepts.
    @ViewBuilder
    private var appearanceControls: some View {
        let materials = nodes.compactMap { appearances[$0.id] }
        if materials.count == nodes.count, !materials.isEmpty {
            baseColorRow(materials)
            numericControl("Opacity", values: materials.map(\.opacity), sliderRange: 0...1) { value in
                commitAppearance(.opacity(value))
            }
            numericControl("Metallic", values: materials.map(\.metallic), sliderRange: 0...1) { value in
                commitAppearance(.metallic(value))
            }
            numericControl("Roughness", values: materials.map(\.roughness), sliderRange: 0...1) { value in
                commitAppearance(.roughness(value))
            }
        }
    }

    private func baseColorRow(_ materials: [RupaCore.Material]) -> some View {
        inspectorControlRow("Color") {
            HStack(spacing: 6) {
                ColorPicker("", selection: baseColorBinding(materials), supportsOpacity: false)
                    .labelsHidden()
                    .controlSize(.small)
                    .disabled(isBusy)
                    .accessibilityIdentifier("WorkspaceObjectTransform.baseColor")
                if commonBaseColor(materials) == nil {
                    Text("Mixed").font(.caption).foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
            }
            .frame(minWidth: inspectorControlWidth, alignment: .leading)
        }
    }

    private func commonBaseColor(_ materials: [RupaCore.Material]) -> ColorRGBA? {
        guard let first = materials.first else { return nil }
        return materials.allSatisfy { $0.baseColor == first.baseColor } ? first.baseColor : nil
    }

    /// The color the swatch shows and the color an edit writes.
    ///
    /// A selection whose nodes disagree shows the first node's color beside a
    /// `Mixed` label rather than a color none of them carries, and an edit there
    /// gives every selected node the color a person picked.
    private func baseColorBinding(_ materials: [RupaCore.Material]) -> Binding<Color> {
        Binding(
            get: {
                guard let color = commonBaseColor(materials) ?? materials.first?.baseColor else {
                    return .clear
                }
                return Color(red: color.r, green: color.g, blue: color.b)
            },
            set: { picked in
                guard !isBusy else { return }
                let resolved = picked.resolve(in: environment)
                let commands: [EditorCommand] = nodes.compactMap { node in
                    guard let material = appearances[node.id] else { return nil }
                    return .setSceneNodeAppearance(
                        id: node.id,
                        edit: .baseColor(
                            ColorRGBA(
                                r: Double(resolved.red),
                                g: Double(resolved.green),
                                b: Double(resolved.blue),
                                a: material.baseColor.a
                            )
                        )
                    )
                }
                guard !commands.isEmpty else { return }
                onCommitProperties(commands, "Change Object Appearance")
            }
        )
    }

    /// Applies one component to every selected node as a single undoable edit.
    func commitAppearance(_ edit: MaterialComponentEdit) {
        guard !isBusy else { return }
        let commands: [EditorCommand] = nodes
            .filter { appearances[$0.id] != nil }
            .map { .setSceneNodeAppearance(id: $0.id, edit: edit) }
        guard !commands.isEmpty else { return }
        onCommitProperties(commands, "Change Object Appearance")
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
                    onCommitProperties(nodes.map { .setSceneNodeTransform(id: $0.id, localTransform: .identity) }, "Reset Object Transforms")
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
