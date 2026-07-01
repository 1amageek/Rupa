import SwiftUI
import RupaCore

enum WorkspaceInspectorLayout {
    static let panelHorizontalInset: CGFloat = 12
    static let panelVerticalInset: CGFloat = 12
    static let sectionSpacing: CGFloat = 12
    static let sectionCornerRadius: CGFloat = 8
    static let sectionHeaderHorizontalPadding: CGFloat = 10
    static let sectionHeaderVerticalPadding: CGFloat = 7
    static let sectionContentVerticalPadding: CGFloat = 4
    static let rowHorizontalPadding: CGFloat = 10
    static let rowVerticalPadding: CGFloat = 5
    static let rowMinimumHeight: CGFloat = 26
    static let rowSpacing: CGFloat = 8
    static let labelWidth: CGFloat = 116
    static let controlWidth: CGFloat = 104
    static let unitWidth: CGFloat = 36
}

let inspectorLabelWidth: CGFloat = WorkspaceInspectorLayout.labelWidth
let inspectorControlWidth: CGFloat = WorkspaceInspectorLayout.controlWidth
let inspectorUnitWidth: CGFloat = WorkspaceInspectorLayout.unitWidth
let inspectorRowSpacing: CGFloat = WorkspaceInspectorLayout.rowSpacing
let inspectorSliderLeadingPadding: CGFloat = WorkspaceInspectorLayout.rowHorizontalPadding
    + inspectorLabelWidth
    + inspectorRowSpacing

struct WorkspaceLengthFieldPresentation: Equatable {
    var meters: Double
    var value: Double
    var unit: LengthDisplayUnit
    var text: String
}

func workspaceLengthFieldPresentation(
    fromMeters meters: Double,
    preferredUnit: LengthDisplayUnit
) -> WorkspaceLengthFieldPresentation {
    let unit = preferredUnit.readableUnit(forMeters: meters)
    let value = unit.value(fromMeters: meters)
    return WorkspaceLengthFieldPresentation(
        meters: meters,
        value: value,
        unit: unit,
        text: WorkspaceInspectorNumberText.string(from: value)
    )
}

func workspaceLengthMeters(
    fromFieldText text: String,
    defaultUnit: LengthDisplayUnit
) -> Double? {
    do {
        return try LengthInputParser().parseMeters(
            from: text,
            defaultUnit: defaultUnit
        )
    } catch {
        return nil
    }
}

@MainActor
func inspectorSection<Content: View>(
    _ title: String,
    @ViewBuilder content: () -> Content
) -> some View {
    VStack(alignment: .leading, spacing: 0) {
        HStack(spacing: 8) {
            Text(title)
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
                .lineLimit(1)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, WorkspaceInspectorLayout.sectionHeaderHorizontalPadding)
        .padding(.vertical, WorkspaceInspectorLayout.sectionHeaderVerticalPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.primary.opacity(0.035))

        VStack(alignment: .leading, spacing: 0) {
            content()
        }
        .padding(.vertical, WorkspaceInspectorLayout.sectionContentVerticalPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(
        RoundedRectangle(cornerRadius: WorkspaceInspectorLayout.sectionCornerRadius, style: .continuous)
            .fill(Color.primary.opacity(0.035))
    )
    .overlay {
        RoundedRectangle(cornerRadius: WorkspaceInspectorLayout.sectionCornerRadius, style: .continuous)
            .strokeBorder(Color.primary.opacity(0.10), lineWidth: 1)
    }
    .clipShape(
        RoundedRectangle(cornerRadius: WorkspaceInspectorLayout.sectionCornerRadius, style: .continuous)
    )
}

@MainActor
func inspectorControlRow<Content: View>(
    _ title: String,
    @ViewBuilder content: () -> Content
) -> some View {
    HStack(alignment: .center, spacing: inspectorRowSpacing) {
        Text(title)
            .font(.callout)
            .foregroundStyle(.secondary)
            .lineLimit(1)
            .frame(width: inspectorLabelWidth, alignment: .leading)
        content()
            .font(.callout)
            .frame(maxWidth: .infinity, alignment: .trailing)
    }
    .padding(.horizontal, WorkspaceInspectorLayout.rowHorizontalPadding)
    .padding(.vertical, WorkspaceInspectorLayout.rowVerticalPadding)
    .frame(minHeight: WorkspaceInspectorLayout.rowMinimumHeight)
    .frame(maxWidth: .infinity, alignment: .leading)
    .overlay(alignment: .bottom) {
        Rectangle()
            .fill(Color.primary.opacity(0.055))
            .frame(height: 1)
            .padding(.leading, WorkspaceInspectorLayout.rowHorizontalPadding + inspectorLabelWidth + inspectorRowSpacing)
    }
}

@MainActor
func inspectorActionRow<Content: View>(
    @ViewBuilder content: () -> Content
) -> some View {
    HStack(spacing: inspectorRowSpacing) {
        Spacer()
            .frame(width: inspectorLabelWidth)
        content()
        Spacer(minLength: 0)
    }
    .padding(.horizontal, WorkspaceInspectorLayout.rowHorizontalPadding)
    .padding(.vertical, WorkspaceInspectorLayout.rowVerticalPadding)
    .frame(minHeight: WorkspaceInspectorLayout.rowMinimumHeight)
    .frame(maxWidth: .infinity, alignment: .leading)
}

@MainActor
func workspaceInspectorValueRow(_ title: String, _ value: String) -> some View {
    inspectorControlRow(title) {
        Text(value)
            .foregroundStyle(.primary.opacity(0.88))
            .fontWeight(.medium)
            .lineLimit(1)
            .truncationMode(.middle)
            .monospacedDigit()
            .textSelection(.enabled)
            .frame(maxWidth: .infinity, alignment: .trailing)
    }
}

@MainActor
func numericControl(
    _ title: String,
    values: [Double],
    sliderRange: ClosedRange<Double>,
    onChange: @escaping (Double) -> Void,
    unitLabel: () -> String = { "" }
) -> some View {
    let commonValue = commonWorkspaceInspectorValue(values)
    let textBinding = Binding<String>(
        get: {
            if let commonValue {
                return WorkspaceInspectorNumberText.string(from: commonValue)
            }
            return "Mixed"
        },
        set: { text in
            guard let value = WorkspaceInspectorNumberText.value(from: text) else {
                return
            }
            onChange(value)
        }
    )
    let sliderBinding = Binding<Double>(
        get: {
            min(max(commonValue ?? 0.0, sliderRange.lowerBound), sliderRange.upperBound)
        },
        set: { value in
            onChange(value)
        }
    )
    let unit = unitLabel()

    return VStack(alignment: .leading, spacing: 4) {
        inspectorControlRow(title) {
            HStack(spacing: 6) {
                TextField(title, text: textBinding)
                    .multilineTextAlignment(.trailing)
                    .frame(width: inspectorControlWidth)
                if !unit.isEmpty {
                    Text(unit)
                        .foregroundStyle(.secondary)
                        .frame(width: inspectorUnitWidth, alignment: .leading)
                }
            }
        }
        Slider(value: sliderBinding, in: sliderRange)
            .padding(.leading, inspectorSliderLeadingPadding)
            .padding(.trailing, WorkspaceInspectorLayout.rowHorizontalPadding)
    }
    .padding(.vertical, 2)
}

func commonWorkspaceInspectorValue(_ values: [Double]) -> Double? {
    guard let first = values.first,
          first.isFinite else {
        return nil
    }
    for value in values {
        guard value.isFinite,
              abs(value - first) <= 1.0e-9 else {
            return nil
        }
    }
    return first
}

@MainActor
func workspaceLengthControl(
    _ title: String,
    values: [Double],
    displayUnit: LengthDisplayUnit,
    sliderRange: ClosedRange<Double>,
    onChange: @escaping (Double) -> Void
) -> some View {
    let commonMeters = commonWorkspaceInspectorValue(values)
    let presentation = commonMeters.map {
        workspaceLengthFieldPresentation(
            fromMeters: $0,
            preferredUnit: displayUnit
        )
    }
    let textBinding = Binding<String>(
        get: {
            if let presentation {
                return presentation.text
            }
            return "Mixed"
        },
        set: { text in
            let defaultUnit = presentation?.unit ?? displayUnit
            guard let meters = workspaceLengthMeters(
                fromFieldText: text,
                defaultUnit: defaultUnit
            ) else {
                return
            }
            onChange(meters)
        }
    )
    let sliderBinding = Binding<Double>(
        get: {
            let value = displayUnit.value(fromMeters: commonMeters ?? 0.0)
            return min(max(value, sliderRange.lowerBound), sliderRange.upperBound)
        },
        set: { value in
            onChange(displayUnit.meters(from: value))
        }
    )
    let unit = presentation?.unit.symbol ?? displayUnit.symbol

    return VStack(alignment: .leading, spacing: 4) {
        inspectorControlRow(title) {
            HStack(spacing: 6) {
                TextField(title, text: textBinding)
                    .multilineTextAlignment(.trailing)
                    .frame(width: inspectorControlWidth)
                Text(unit)
                    .foregroundStyle(.secondary)
                    .frame(width: inspectorUnitWidth, alignment: .leading)
            }
        }
        Slider(value: sliderBinding, in: sliderRange)
            .padding(.leading, inspectorSliderLeadingPadding)
            .padding(.trailing, WorkspaceInspectorLayout.rowHorizontalPadding)
    }
    .padding(.vertical, 2)
}
