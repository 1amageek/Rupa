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
            displayUnitPicker
        }

        inspectorSection("Ruler") {
            rulerLengthControl(
                "Minor",
                meters: state.ruler.minorTickMeters,
                sliderRange: 0.01 ... 100.0,
                onChange: setMinorTickMeters
            )
            rulerLengthControl(
                "Major",
                meters: state.ruler.majorTickMeters,
                sliderRange: 0.1 ... 1_000.0,
                onChange: setMajorTickMeters
            )
            rulerLengthControl(
                "Visible",
                meters: state.ruler.visibleSpanMeters,
                sliderRange: 1.0 ... 100_000.0,
                onChange: setVisibleSpanMeters
            )
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
        meters: Double,
        sliderRange: ClosedRange<Double>,
        onChange: @escaping (Double) -> Void
    ) -> some View {
        let unit = state.displayUnit
        return numericControl(
            title,
            values: [unit.value(fromMeters: meters)],
            sliderRange: sliderRange
        ) { value in
            onChange(unit.meters(from: max(value, 0.0)))
        } unitLabel: {
            unit.symbol
        }
    }
}
