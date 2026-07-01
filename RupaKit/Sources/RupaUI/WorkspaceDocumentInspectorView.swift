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
    var scaleRecommendation: WorkspaceDocumentScaleRecommendationState?
    var precisionRecommendation: WorkspaceDocumentPrecisionRecommendationState?
    var parameters: WorkspaceParameterInspectorState
}

struct WorkspaceDocumentScaleRecommendationState: Equatable, Sendable {
    var reasonTitle: String
    var presetTitle: String
    var visibleSpanTitle: String
    var preset: WorkspaceScalePreset
}

struct WorkspaceDocumentPrecisionRecommendationState: Equatable, Sendable {
    var reasonTitle: String
    var originDistanceTitle: String
    var modelSpanTitle: String
    var translationTitle: String
    var translation: Vector3D
}

struct WorkspaceDocumentInspectorView: View {
    var state: WorkspaceDocumentInspectorState
    var setDisplayUnit: (LengthDisplayUnit) -> Void
    var setWorkspaceScalePreset: (WorkspaceScalePreset) -> Void
    var applyWorkspaceRebaseTranslation: (Vector3D) -> Void
    var setMinorTickMeters: (Double) -> Void
    var setMajorTickMeters: (Double) -> Void
    var setVisibleSpanMeters: (Double) -> Void
    var renameParameter: (String, String) -> Bool
    var upsertParameterExpression: (String, String, QuantityKind) -> Bool
    var deleteParameter: (String) -> Bool

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
            if let scaleRecommendation = state.scaleRecommendation {
                scaleRecommendationControl(scaleRecommendation)
            }
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

        if let precisionRecommendation = state.precisionRecommendation {
            inspectorSection("Precision") {
                precisionRecommendationControl(precisionRecommendation)
            }
        }

        WorkspaceParameterInspectorView(
            state: state.parameters,
            onRename: renameParameter,
            onUpsert: upsertParameterExpression,
            onDelete: deleteParameter
        )
    }

    private var scalePresetMenu: some View {
        let selectedTitle = WorkspaceScalePreset.matching(state.ruler)?.title ?? "Custom"
        return inspectorControlRow("Scale Preset") {
            Menu {
                ForEach(WorkspaceScalePreset.allCases) { preset in
                    let profile = preset.profile
                    Button {
                        setWorkspaceScalePreset(preset)
                    } label: {
                        Text(profile.menuTitle)
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

    private func scaleRecommendationControl(
        _ recommendation: WorkspaceDocumentScaleRecommendationState
    ) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            inspectorControlRow("Recommended") {
                Button {
                    setWorkspaceScalePreset(recommendation.preset)
                } label: {
                    HStack(spacing: 6) {
                        Text(recommendation.presetTitle)
                            .lineLimit(1)
                            .truncationMode(.tail)
                        Spacer(minLength: 4)
                        Image(systemName: "arrow.right.circle")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    .frame(width: inspectorControlWidth + inspectorUnitWidth + 6)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .accessibilityIdentifier("WorkspaceScaleRecommendation.apply")
            }
            workspaceInspectorValueRow("Reason", recommendation.reasonTitle)
            workspaceInspectorValueRow("Visible Span", recommendation.visibleSpanTitle)
        }
        .padding(.vertical, 2)
    }

    private func precisionRecommendationControl(
        _ recommendation: WorkspaceDocumentPrecisionRecommendationState
    ) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            inspectorControlRow("Recommended") {
                Button {
                    applyWorkspaceRebaseTranslation(recommendation.translation)
                } label: {
                    HStack(spacing: 6) {
                        Text("Rebase Origin")
                            .lineLimit(1)
                            .truncationMode(.tail)
                        Spacer(minLength: 4)
                        Image(systemName: "scope")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    .frame(width: inspectorControlWidth + inspectorUnitWidth + 6)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .accessibilityIdentifier("WorkspacePrecisionRecommendation.apply")
            }
            workspaceInspectorValueRow("Reason", recommendation.reasonTitle)
            workspaceInspectorValueRow("Origin", recommendation.originDistanceTitle)
            workspaceInspectorValueRow("Span", recommendation.modelSpanTitle)
            workspaceInspectorValueRow("Move", recommendation.translationTitle)
        }
        .padding(.vertical, 2)
    }

    private func rulerLengthControl(
        _ title: String,
        kind: RulerScaleControl.Kind,
        meters: Double,
        onChange: @escaping (Double) -> Void
    ) -> some View {
        let presentation = RulerScaleControl.fieldPresentation(
            fromMeters: meters,
            preferredUnit: state.displayUnit,
            for: kind
        )
        let unit = presentation.unit
        let textBinding = Binding<String>(
            get: {
                presentation.text
            },
            set: { text in
                guard let meters = RulerScaleControl.meters(
                    fromFieldText: text,
                    unit: unit,
                    for: kind
                ) else {
                    return
                }
                onChange(meters)
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

func workspaceDocumentPrecisionRecommendationState(
    report: WorkspacePrecisionReport?,
    displayUnit: LengthDisplayUnit
) -> WorkspaceDocumentPrecisionRecommendationState? {
    guard let report,
          let translation = report.recommendedRebaseTranslation else {
        return nil
    }
    return WorkspaceDocumentPrecisionRecommendationState(
        reasonTitle: workspacePrecisionReasonTitle(report.reason),
        originDistanceTitle: workspacePrecisionLengthTitle(
            report.originDistanceMeters,
            displayUnit: displayUnit
        ),
        modelSpanTitle: workspacePrecisionLengthTitle(
            report.modelSpanMeters,
            displayUnit: displayUnit
        ),
        translationTitle: workspacePrecisionTranslationTitle(
            translation,
            displayUnit: displayUnit
        ),
        translation: translation
    )
}

private func workspacePrecisionReasonTitle(
    _ reason: WorkspacePrecisionReport.Reason
) -> String {
    switch reason {
    case .coordinateResolution:
        "Coordinate resolution"
    case .farFromOrigin:
        "Far from origin"
    }
}

private func workspacePrecisionTranslationTitle(
    _ translation: Vector3D,
    displayUnit: LengthDisplayUnit
) -> String {
    [
        "x \(workspacePrecisionLengthTitle(translation.x, displayUnit: displayUnit))",
        "y \(workspacePrecisionLengthTitle(translation.y, displayUnit: displayUnit))",
        "z \(workspacePrecisionLengthTitle(translation.z, displayUnit: displayUnit))",
    ].joined(separator: ", ")
}

private func workspacePrecisionLengthTitle(
    _ meters: Double,
    displayUnit: LengthDisplayUnit
) -> String {
    let unit = displayUnit.readableUnit(forMeters: meters)
    return LengthDisplayText.lengthString(
        fromMeters: meters,
        unit: unit,
        maximumFractionDigits: 3
    )
}
