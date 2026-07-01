import RupaCore
import SwiftUI

struct WorkspaceDocumentInspectorState: Equatable, Sendable {
    var documentName: String
    var documentID: String
    var sourceUnitTitle: String
    var displayUnit: LengthDisplayUnit
    var sourceFeatureCount: Int
    var sceneNodeCount: Int
    var selectedCount: Int
    var generatedBodyCount: Int
    var componentCount: Int
    var instanceCount: Int
    var evaluationTitle: String
    var diagnosticSummary: String
    var renderReasonTitle: String
    var renderGenerationTitle: String
    var materialCount: Int
    var defaultMaterialTitle: String
    var validationRuleCount: Int
    var exportPresetCount: Int
    var ruler: RulerConfiguration
}

struct WorkspaceDocumentInspectorView: View {
    var state: WorkspaceDocumentInspectorState
    var setDisplayUnit: (LengthDisplayUnit) -> Void
    var setWorkspaceScalePreset: (WorkspaceScalePreset) -> Void
    var setMinorTickMeters: (Double) -> Void
    var setMajorTickMeters: (Double) -> Void
    var setVisibleSpanMeters: (Double) -> Void

    var body: some View {
        inspectorSection("Document") {
            workspaceInspectorValueRow("Name", state.documentName)
            workspaceInspectorValueRow("Document ID", state.documentID)
            workspaceInspectorValueRow("Source Unit", state.sourceUnitTitle)
            workspaceInspectorValueRow("Display Unit", state.displayUnit.symbol)
        }

        inspectorSection("Scene") {
            workspaceInspectorValueRow("Source Features", "\(state.sourceFeatureCount)")
            workspaceInspectorValueRow("Scene Nodes", "\(state.sceneNodeCount)")
            workspaceInspectorValueRow("Selected", "\(state.selectedCount)")
            workspaceInspectorValueRow("Generated Bodies", "\(state.generatedBodyCount)")
            workspaceInspectorValueRow("Components", "\(state.componentCount)")
            workspaceInspectorValueRow("Instances", "\(state.instanceCount)")
        }

        inspectorSection("Evaluation") {
            workspaceInspectorValueRow("Evaluation", state.evaluationTitle)
            workspaceInspectorValueRow("Diagnostics", state.diagnosticSummary)
            workspaceInspectorValueRow("Render Reason", state.renderReasonTitle)
            workspaceInspectorValueRow("Render Generation", state.renderGenerationTitle)
        }

        inspectorSection("Assets") {
            workspaceInspectorValueRow("Materials", "\(state.materialCount)")
            workspaceInspectorValueRow("Default Material", state.defaultMaterialTitle)
            workspaceInspectorValueRow("Validation Rules", "\(state.validationRuleCount)")
            workspaceInspectorValueRow("Export Presets", "\(state.exportPresetCount)")
        }

        inspectorSection("Units") {
            scalePresetMenu
            displayUnitPicker
        }

        inspectorSection("Ruler") {
            rulerLengthControl(
                "Minor",
                kind: .minor,
                meters: state.ruler.minorTickMeters,
                onChange: setMinorTickMeters
            )
            rulerLengthControl(
                "Major",
                kind: .major,
                meters: state.ruler.majorTickMeters,
                onChange: setMajorTickMeters
            )
            rulerLengthControl(
                "Visible",
                kind: .visible,
                meters: state.ruler.visibleSpanMeters,
                onChange: setVisibleSpanMeters
            )
        }
    }

    private var scalePresetMenu: some View {
        let selectedTitle = WorkspaceScalePreset.matching(state.ruler)?.title ?? "Custom"
        return inspectorControlRow("Scale Preset") {
            Menu {
                ForEach(WorkspaceScalePreset.allCases) { preset in
                    Button(preset.title) {
                        setWorkspaceScalePreset(preset)
                    }
                }
            } label: {
                HStack(spacing: 6) {
                    Text(selectedTitle)
                        .lineLimit(1)
                        .truncationMode(.tail)
                    Spacer(minLength: 4)
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                .frame(width: inspectorControlWidth + inspectorUnitWidth + 6)
            }
            .controlSize(.small)
        }
    }

    private var displayUnitPicker: some View {
        inspectorControlRow("Display Unit") {
            Picker(
                "",
                selection: Binding(
                    get: { state.displayUnit },
                    set: { unit in
                        setDisplayUnit(unit)
                    }
                )
            ) {
                ForEach(LengthDisplayUnit.allCases) { unit in
                    Text(unit.symbol)
                        .tag(unit)
                }
            }
            .labelsHidden()
            .controlSize(.small)
            .frame(width: inspectorControlWidth)
        }
    }

    private func rulerLengthControl(
        _ title: String,
        kind: RulerScaleControl.Kind,
        meters: Double,
        onChange: @escaping (Double) -> Void
    ) -> some View {
        let unit = state.displayUnit
        let textBinding = Binding<String>(
            get: {
                let value = RulerScaleControl.fieldValue(
                    fromMeters: meters,
                    unit: unit,
                    for: kind
                )
                return value.formatted(.number.precision(.fractionLength(0...6)))
            },
            set: { text in
                let trimmedText = text.trimmingCharacters(in: .whitespacesAndNewlines)
                guard let value = Double(trimmedText), value.isFinite else {
                    return
                }
                onChange(
                    RulerScaleControl.meters(
                        fromFieldValue: value,
                        unit: unit,
                        for: kind
                    )
                )
            }
        )
        let sliderBinding = Binding<Double>(
            get: {
                RulerScaleControl.sliderValue(fromMeters: meters, for: kind)
            },
            set: { value in
                onChange(RulerScaleControl.meters(fromSliderValue: value, for: kind))
            }
        )

        return VStack(alignment: .leading, spacing: 4) {
            inspectorControlRow(title) {
                HStack(spacing: 6) {
                    TextField(title, text: textBinding)
                        .multilineTextAlignment(.trailing)
                        .frame(width: inspectorControlWidth)
                    Text(unit.symbol)
                        .foregroundStyle(.secondary)
                        .frame(width: inspectorUnitWidth, alignment: .leading)
                }
            }
            Slider(value: sliderBinding, in: RulerScaleControl.sliderRange(for: kind))
                .padding(.leading, inspectorSliderLeadingPadding)
                .padding(.trailing, WorkspaceInspectorLayout.rowHorizontalPadding)
        }
        .padding(.vertical, 2)
    }
}
