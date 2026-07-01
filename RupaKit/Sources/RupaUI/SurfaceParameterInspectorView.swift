import RupaCore
import SwiftUI

@MainActor
struct SurfaceParameterInspectorView: View {
    let state: SurfaceParameterInspectorState
    @Binding var knotInsertionValue: Double
    @Binding var spanSplitFraction: Double
    @Binding var knotMultiplicityValue: Int
    let onSetKnotValue: (SelectionReference, Double) -> Void
    let onInsertKnot: (SelectionReference, Double) -> Void
    let onSplitSpan: (SelectionReference, Double) -> Void
    let onSetKnotMultiplicity: (SelectionReference, Int) -> Void
    let onSetFrameDisplay: ([SurfaceFrameQuery], Bool) -> Void

    var body: some View {
        inspectorSection("Surface Parameter") {
            inspectorRow("Parameters", "\(state.selectionCount)")
            inspectorRow("Source", state.sourceTitle)
            inspectorRow("Patch", state.patchTitle)
            inspectorRow("Basis", state.basisTitle)
            inspectorRow("Kind", state.kindTitle)
            inspectorRow("Direction", state.directionTitle)
            inspectorRow("Index", state.indexTitle)
            inspectorRow("Value", state.valueTitle)
            inspectorRow("Multiplicity", state.multiplicityTitle)
            inspectorRow("Boundary", state.boundaryTitle)
            inspectorRow("Edit", state.editabilityTitle)
            frameDisplayStatus
            knotValueControl
            multiplicityControl
            spanSplitControl
            insertionControl
            frameDetailRows
            frameDisplayControls
        }
    }

    @ViewBuilder
    private var frameDisplayStatus: some View {
        if state.canToggleFrameDisplay {
            inspectorRow("Frame Display", state.frameDisplayTitle)
        }
    }

    @ViewBuilder
    private var knotValueControl: some View {
        if state.canSetKnotValue,
           let entry = state.entries.first,
           let value = entry.value,
           let range = entry.knotValueRange {
            scalarControl(
                "Set",
                value: value,
                sliderRange: range
            ) { newValue in
                guard let clampedValue = state.clampedKnotValue(newValue) else {
                    return
                }
                onSetKnotValue(entry.selectionReference, clampedValue)
            }
            .accessibilityIdentifier("InspectorSurfaceParameter.knot.value")
        }
    }

    @ViewBuilder
    private var multiplicityControl: some View {
        if state.canSetKnotMultiplicity,
           let entry = state.entries.first,
           let range = entry.knotMultiplicityRange {
            inspectorControlRow("Set Mult.") {
                HStack(spacing: 8) {
                    Text("\(multiplicityDraftValue(range: range))")
                        .monospacedDigit()
                        .frame(width: 28, alignment: .trailing)
                    Stepper(
                        "",
                        value: multiplicityBinding(range: range),
                        in: range
                    )
                    .labelsHidden()
                }
            }
            .accessibilityIdentifier("InspectorSurfaceParameter.knot.multiplicityValue")

            inspectorActionRow {
                inspectorIconButton(
                    systemImage: "checkmark",
                    help: "Set Surface Knot Multiplicity",
                    accessibilityIdentifier: "InspectorSurfaceParameter.knot.multiplicity"
                ) {
                    guard let clampedValue = state.clampedKnotMultiplicity(
                        multiplicityDraftValue(range: range)
                    ) else {
                        return
                    }
                    knotMultiplicityValue = clampedValue
                    onSetKnotMultiplicity(entry.selectionReference, clampedValue)
                }
            }
        }
    }

    @ViewBuilder
    private var spanSplitControl: some View {
        if state.canSplitSpan,
           let entry = state.entries.first {
            draftScalarControl(
                "Split",
                value: spanSplitFractionBinding,
                sliderRange: 0.01 ... 0.99
            )
            .accessibilityIdentifier("InspectorSurfaceParameter.span.splitFraction")

            inspectorActionRow {
                inspectorIconButton(
                    systemImage: "square.split.2x1",
                    help: "Split Surface Span",
                    accessibilityIdentifier: "InspectorSurfaceParameter.span.split"
                ) {
                    guard let fraction = state.clampedSpanSplitFraction(spanSplitFraction) else {
                        return
                    }
                    spanSplitFraction = fraction
                    onSplitSpan(entry.selectionReference, fraction)
                }
            }
        }
    }

    @ViewBuilder
    private var insertionControl: some View {
        if state.canInsertKnot,
           let entry = state.entries.first {
            switch entry.kind {
            case .address:
                EmptyView()
            case .knot:
                insertionActionRow(entry: entry, value: entry.value ?? 0.0)
            case .span:
                if let range = entry.insertionRange {
                    draftScalarControl(
                        "Insert",
                        value: insertionBinding(range: range),
                        sliderRange: range
                    )
                    .accessibilityIdentifier("InspectorSurfaceParameter.knot.insertValue")
                    insertionActionRow(
                        entry: entry,
                        value: insertionDraftValue(range: range)
                    )
                }
            }
        }
    }

    @ViewBuilder
    private var frameDetailRows: some View {
        if state.hasResolvedFrames {
            inspectorRow("Position", state.framePositionTitle)
            inspectorRow("U Axis", state.frameUAxisTitle)
            inspectorRow("V Axis", state.frameVAxisTitle)
            inspectorRow("Normal", state.frameNormalTitle)
            inspectorRow("Handedness", state.frameHandednessTitle)
            inspectorRow("Normal Curvature", state.frameNormalCurvatureTitle)
            inspectorRow("Principal Curvature", state.framePrincipalCurvatureTitle)
            inspectorRow("Gaussian Curvature", state.frameGaussianCurvatureTitle)
        }
    }

    @ViewBuilder
    private var frameDisplayControls: some View {
        if state.canToggleFrameDisplay {
            inspectorActionRow {
                inspectorIconButton(
                    systemImage: "scope",
                    help: "Show Surface UVN Frame",
                    accessibilityIdentifier: "InspectorSurfaceParameter.frameDisplay.show"
                ) {
                    onSetFrameDisplay(state.selectedFrameQueries, true)
                }
                .disabled(state.entries.allSatisfy(\.isFrameDisplayVisible))

                inspectorIconButton(
                    systemImage: "scope",
                    help: "Hide Surface UVN Frame",
                    accessibilityIdentifier: "InspectorSurfaceParameter.frameDisplay.hide"
                ) {
                    onSetFrameDisplay(state.selectedFrameQueries, false)
                }
                .disabled(state.entries.allSatisfy { !$0.isFrameDisplayVisible })
            }
        }
    }

    private var spanSplitFractionBinding: Binding<Double> {
        Binding<Double>(
            get: {
                state.clampedSpanSplitFraction(spanSplitFraction)
                    ?? state.defaultSpanSplitFraction()
            },
            set: { newValue in
                guard let fraction = state.clampedSpanSplitFraction(newValue) else {
                    return
                }
                spanSplitFraction = fraction
            }
        )
    }

    private func insertionActionRow(
        entry: SurfaceParameterInspectorState.Entry,
        value: Double
    ) -> some View {
        inspectorActionRow {
            inspectorIconButton(
                systemImage: "plus",
                help: "Insert Surface Knot",
                accessibilityIdentifier: "InspectorSurfaceParameter.knot.insert"
            ) {
                guard let clampedValue = state.clampedInsertionValue(value) else {
                    return
                }
                knotInsertionValue = clampedValue
                onInsertKnot(entry.selectionReference, clampedValue)
            }
        }
    }

    private func multiplicityDraftValue(range: ClosedRange<Int>) -> Int {
        if range.contains(knotMultiplicityValue) {
            return knotMultiplicityValue
        }
        return state.defaultKnotMultiplicity(fallback: range.lowerBound)
    }

    private func multiplicityBinding(range: ClosedRange<Int>) -> Binding<Int> {
        Binding<Int>(
            get: {
                multiplicityDraftValue(range: range)
            },
            set: { newValue in
                knotMultiplicityValue = min(max(newValue, range.lowerBound), range.upperBound)
            }
        )
    }

    private func insertionDraftValue(range: ClosedRange<Double>) -> Double {
        if knotInsertionValue.isFinite,
           range.contains(knotInsertionValue) {
            return knotInsertionValue
        }
        return state.defaultInsertionValue(fallback: (range.lowerBound + range.upperBound) * 0.5)
    }

    private func insertionBinding(range: ClosedRange<Double>) -> Binding<Double> {
        Binding<Double>(
            get: {
                insertionDraftValue(range: range)
            },
            set: { newValue in
                guard newValue.isFinite else {
                    return
                }
                knotInsertionValue = min(max(newValue, range.lowerBound), range.upperBound)
            }
        )
    }

    private func scalarControl(
        _ title: String,
        value: Double,
        sliderRange: ClosedRange<Double>,
        onChange: @escaping (Double) -> Void
    ) -> some View {
        let textBinding = Binding<String>(
            get: {
                WorkspaceInspectorNumberText.string(from: value)
            },
            set: { text in
                guard let newValue = WorkspaceInspectorNumberText.value(from: text) else {
                    return
                }
                onChange(newValue)
            }
        )
        let sliderBinding = Binding<Double>(
            get: {
                min(max(value, sliderRange.lowerBound), sliderRange.upperBound)
            },
            set: { newValue in
                onChange(newValue)
            }
        )

        return VStack(alignment: .leading, spacing: 5) {
            inspectorControlRow(title) {
                TextField(title, text: textBinding)
                    .multilineTextAlignment(.trailing)
                    .frame(width: inspectorControlWidth)
            }
            Slider(value: sliderBinding, in: sliderRange)
                .padding(.leading, inspectorSliderLeadingPadding)
        }
        .padding(.vertical, 1)
    }

    private func draftScalarControl(
        _ title: String,
        value: Binding<Double>,
        sliderRange: ClosedRange<Double>
    ) -> some View {
        let textBinding = Binding<String>(
            get: {
                WorkspaceInspectorNumberText.string(from: value.wrappedValue)
            },
            set: { text in
                guard let newValue = WorkspaceInspectorNumberText.value(from: text) else {
                    return
                }
                value.wrappedValue = newValue
            }
        )
        let sliderBinding = Binding<Double>(
            get: {
                min(max(value.wrappedValue, sliderRange.lowerBound), sliderRange.upperBound)
            },
            set: { newValue in
                value.wrappedValue = newValue
            }
        )

        return VStack(alignment: .leading, spacing: 5) {
            inspectorControlRow(title) {
                TextField(title, text: textBinding)
                    .multilineTextAlignment(.trailing)
                    .frame(width: inspectorControlWidth)
            }
            Slider(value: sliderBinding, in: sliderRange)
                .padding(.leading, inspectorSliderLeadingPadding)
        }
        .padding(.vertical, 1)
    }

    private func inspectorIconButton(
        systemImage: String,
        help: String,
        accessibilityIdentifier: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .frame(width: 16, height: 16)
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
        .help(help)
        .accessibilityLabel(help)
        .accessibilityIdentifier(accessibilityIdentifier)
    }

    private func inspectorSection<Content: View>(
        _ title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
                .frame(maxWidth: .infinity, alignment: .leading)

            VStack(alignment: .leading, spacing: 8) {
                content()
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func inspectorRow(_ title: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: inspectorRowSpacing) {
            Text(title)
                .foregroundStyle(.secondary)
                .frame(width: inspectorLabelWidth, alignment: .leading)
            Text(value)
                .lineLimit(1)
                .truncationMode(.middle)
                .monospacedDigit()
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .font(.callout)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func inspectorControlRow<Content: View>(
        _ title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        HStack(alignment: .center, spacing: inspectorRowSpacing) {
            Text(title)
                .foregroundStyle(.secondary)
                .frame(width: inspectorLabelWidth, alignment: .leading)
            content()
                .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .font(.callout)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func inspectorActionRow<Content: View>(
        @ViewBuilder content: () -> Content
    ) -> some View {
        HStack(spacing: 6) {
            Spacer()
                .frame(width: inspectorLabelWidth)
            content()
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var inspectorLabelWidth: CGFloat { 124 }
    private var inspectorControlWidth: CGFloat { 104 }
    private var inspectorRowSpacing: CGFloat { 10 }
    private var inspectorSliderLeadingPadding: CGFloat {
        inspectorLabelWidth + inspectorRowSpacing
    }
}
