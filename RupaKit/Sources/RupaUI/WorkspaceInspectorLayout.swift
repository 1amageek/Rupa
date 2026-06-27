import SwiftUI

let inspectorLabelWidth: CGFloat = 124
let inspectorControlWidth: CGFloat = 104
let inspectorUnitWidth: CGFloat = 36
let inspectorRowSpacing: CGFloat = 10
let inspectorSliderLeadingPadding: CGFloat = inspectorLabelWidth + inspectorRowSpacing

@MainActor
func inspectorSection<Content: View>(
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

@MainActor
func inspectorControlRow<Content: View>(
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
    .frame(maxWidth: .infinity, alignment: .leading)
}

@MainActor
func workspaceInspectorValueRow(_ title: String, _ value: String) -> some View {
    inspectorControlRow(title) {
        Text(value)
            .lineLimit(1)
            .truncationMode(.middle)
            .monospacedDigit()
            .textSelection(.enabled)
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
                return commonValue.formatted(.number.precision(.fractionLength(0...6)))
            }
            return "Mixed"
        },
        set: { text in
            let trimmedText = text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard let value = Double(trimmedText), value.isFinite else {
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

    return VStack(alignment: .leading, spacing: 5) {
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
    }
    .padding(.vertical, 1)
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
