import SwiftUI
import RupaCore

enum WorkspaceInspectorLayout {
    static let minimumColumnWidth: CGFloat = 320
    static let idealColumnWidth: CGFloat = 320
    static let panelHorizontalInset: CGFloat = 12
    static let panelVerticalInset: CGFloat = 12
    static let sectionSpacing: CGFloat = 12
    static let sectionCornerRadius: CGFloat = 8
    static let sectionHeaderHorizontalPadding: CGFloat = 10
    static let sectionHeaderVerticalPadding: CGFloat = 7
    static let sectionContentVerticalPadding: CGFloat = 4
    static let rowHorizontalPadding: CGFloat = 10
    static let rowVerticalPadding: CGFloat = 2
    static let rowMinimumHeight: CGFloat = 26
    static let rowSpacing: CGFloat = 4
    static let labelWidth: CGFloat = 64
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

enum WorkspaceLengthFieldPresentationPolicy: Equatable, Sendable {
    case editing
    case workspaceScale

    var allowsKilometers: Bool {
        switch self {
        case .editing:
            true
        case .workspaceScale:
            true
        }
    }
}

struct WorkspaceLengthSliderScale: Equatable {
    private static let logarithmicRatioThreshold = 1_000.0
    private static let logarithmicSpanThresholdMeters = 1_000.0
    private static let minimumPositiveMeters = 1.0e-9

    var metersRange: ClosedRange<Double>

    init(metersRange: ClosedRange<Double>) {
        let lower = metersRange.lowerBound.isFinite ? metersRange.lowerBound : 0.0
        let upper = metersRange.upperBound.isFinite ? metersRange.upperBound : 1.0
        if lower <= upper {
            self.metersRange = lower ... upper
        } else {
            self.metersRange = upper ... lower
        }
    }

    func sliderValue(forMeters meters: Double) -> Double {
        let meters = clampedMeters(meters)
        if usesSymmetricLogarithmicScale {
            return symmetricSliderValue(forMeters: meters)
        }
        if usesPositiveLogarithmicScale {
            return positiveLogarithmicSliderValue(forMeters: meters)
        }
        return linearSliderValue(forMeters: meters)
    }

    func meters(fromSliderValue value: Double) -> Double {
        let value = min(max(value, 0.0), 1.0)
        if usesSymmetricLogarithmicScale {
            return clampedMeters(symmetricMeters(fromSliderValue: value))
        }
        if usesPositiveLogarithmicScale {
            return clampedMeters(positiveLogarithmicMeters(fromSliderValue: value))
        }
        return clampedMeters(linearMeters(fromSliderValue: value))
    }

    private var span: Double {
        metersRange.upperBound - metersRange.lowerBound
    }

    private var usesPositiveLogarithmicScale: Bool {
        guard metersRange.lowerBound >= 0.0,
              metersRange.upperBound >= Self.logarithmicSpanThresholdMeters else {
            return false
        }
        let lower = max(metersRange.lowerBound, Self.minimumPositiveMeters)
        return metersRange.upperBound / lower >= Self.logarithmicRatioThreshold
    }

    private var usesSymmetricLogarithmicScale: Bool {
        guard metersRange.lowerBound < 0.0,
              metersRange.upperBound > 0.0 else {
            return false
        }
        let maxMagnitude = max(abs(metersRange.lowerBound), abs(metersRange.upperBound))
        return maxMagnitude >= Self.logarithmicSpanThresholdMeters
    }

    private func clampedMeters(_ meters: Double) -> Double {
        guard meters.isFinite else {
            return metersRange.lowerBound
        }
        return min(max(meters, metersRange.lowerBound), metersRange.upperBound)
    }

    private func linearSliderValue(forMeters meters: Double) -> Double {
        guard span > 0.0 else {
            return 0.0
        }
        return min(max((meters - metersRange.lowerBound) / span, 0.0), 1.0)
    }

    private func linearMeters(fromSliderValue value: Double) -> Double {
        metersRange.lowerBound + span * value
    }

    private func positiveLogarithmicSliderValue(forMeters meters: Double) -> Double {
        if meters <= 0.0, metersRange.lowerBound <= 0.0 {
            return 0.0
        }
        let lower = max(metersRange.lowerBound, Self.minimumPositiveMeters)
        let upper = max(metersRange.upperBound, lower)
        let ratio = log(upper / lower)
        guard ratio > 0.0 else {
            return 0.0
        }
        let value = max(meters, lower)
        return min(max(log(value / lower) / ratio, 0.0), 1.0)
    }

    private func positiveLogarithmicMeters(fromSliderValue value: Double) -> Double {
        if value <= 0.0, metersRange.lowerBound <= 0.0 {
            return metersRange.lowerBound
        }
        let lower = max(metersRange.lowerBound, Self.minimumPositiveMeters)
        let upper = max(metersRange.upperBound, lower)
        return lower * pow(upper / lower, value)
    }

    private func symmetricSliderValue(forMeters meters: Double) -> Double {
        guard meters != 0.0 else {
            return 0.5
        }
        let maxMagnitude = max(abs(metersRange.lowerBound), abs(metersRange.upperBound), Self.minimumPositiveMeters)
        let magnitude = max(abs(meters), Self.minimumPositiveMeters)
        let progress = min(max(log(magnitude / Self.minimumPositiveMeters) / log(maxMagnitude / Self.minimumPositiveMeters), 0.0), 1.0)
        if meters > 0.0 {
            return 0.5 + progress * 0.5
        }
        return 0.5 - progress * 0.5
    }

    private func symmetricMeters(fromSliderValue value: Double) -> Double {
        guard value != 0.5 else {
            return 0.0
        }
        let maxMagnitude = max(abs(metersRange.lowerBound), abs(metersRange.upperBound), Self.minimumPositiveMeters)
        let progress = abs(value - 0.5) * 2.0
        let magnitude = Self.minimumPositiveMeters * pow(maxMagnitude / Self.minimumPositiveMeters, progress)
        return value > 0.5 ? magnitude : -magnitude
    }
}

struct WorkspaceScaleFactorSliderScale: Equatable {
    static let defaultMinimumValue = 1.0e-9
    static let defaultMaximumValue = 1.0e9

    var valueRange: ClosedRange<Double>

    init(valueRange: ClosedRange<Double>) {
        let lower = valueRange.lowerBound.isFinite && valueRange.lowerBound > 0.0
            ? valueRange.lowerBound
            : Self.defaultMinimumValue
        let upper = valueRange.upperBound.isFinite
            ? max(valueRange.upperBound, lower * 10.0)
            : Self.defaultMaximumValue
        self.valueRange = lower ... upper
    }

    func sliderValue(for value: Double) -> Double {
        let value = clampedValue(value)
        let ratio = log(valueRange.upperBound / valueRange.lowerBound)
        guard ratio > 0.0 else {
            return 0.0
        }
        return min(max(log(value / valueRange.lowerBound) / ratio, 0.0), 1.0)
    }

    func value(fromSliderValue sliderValue: Double) -> Double {
        let progress = min(max(sliderValue, 0.0), 1.0)
        let value = valueRange.lowerBound * pow(valueRange.upperBound / valueRange.lowerBound, progress)
        return clampedValue(value)
    }

    private func clampedValue(_ value: Double) -> Double {
        guard value.isFinite else {
            return 1.0
        }
        return min(max(value, valueRange.lowerBound), valueRange.upperBound)
    }
}

func workspaceLengthSliderMetersRange(
    for meters: Double,
    ruler: RulerConfiguration,
    expansionMultiplier: Double = 4.0
) -> ClosedRange<Double> {
    let normalizedRuler = ruler.normalizedForWorkspaceScale()
    let currentMeters = meters.isFinite ? abs(meters) : 0.0
    let upperMeters = max(
        currentMeters * expansionMultiplier,
        normalizedRuler.visibleSpanMeters,
        normalizedRuler.minorTickMeters,
        RulerConfiguration.visibleSpanMetersRange.lowerBound
    )
    return 0.0 ... upperMeters
}

func workspaceLengthInteractionSliderMetersRange(
    for values: [Double],
    fallbackRange: ClosedRange<Double>,
    validationRange: ObjectPropertyDefinition.NumericRange? = nil,
    expansionMultiplier: Double = 4.0
) -> ClosedRange<Double> {
    let currentMaximum = values
        .filter { $0.isFinite }
        .map(abs)
        .max() ?? 0.0
    let fallbackUpper = max(
        fallbackRange.upperBound,
        fallbackRange.lowerBound,
        currentMaximum * expansionMultiplier
    )
    let unclampedLower = min(fallbackRange.lowerBound, fallbackUpper)
    let unclampedRange = unclampedLower ... fallbackUpper
    guard let validationRange else {
        return unclampedRange
    }

    let lower = max(unclampedRange.lowerBound, validationRange.lowerBound)
    let upper = min(
        max(unclampedRange.upperBound, currentMaximum, lower),
        validationRange.upperBound
    )
    guard upper > lower else {
        return validationRange.lowerBound ... validationRange.upperBound
    }
    return lower ... upper
}

func workspaceSignedLengthSliderMetersRange(
    for meters: Double,
    ruler: RulerConfiguration,
    expansionMultiplier: Double = 2.0
) -> ClosedRange<Double> {
    let normalizedRuler = ruler.normalizedForWorkspaceScale()
    let currentMeters = meters.isFinite ? abs(meters) : 0.0
    let extentMeters = max(
        currentMeters * expansionMultiplier,
        normalizedRuler.visibleSpanMeters,
        normalizedRuler.minorTickMeters,
        RulerConfiguration.visibleSpanMetersRange.lowerBound
    )
    return -extentMeters ... extentMeters
}

func workspaceScaleFactorSliderRange(
    for values: [Double]
) -> ClosedRange<Double> {
    let positiveValues = values.filter { $0.isFinite && $0 > 0.0 }
    let currentMinimum = positiveValues.min() ?? 1.0
    let currentMaximum = positiveValues.max() ?? 1.0
    let lower = min(
        WorkspaceScaleFactorSliderScale.defaultMinimumValue,
        currentMinimum / 10.0
    )
    let upper = max(
        WorkspaceScaleFactorSliderScale.defaultMaximumValue,
        currentMaximum * 10.0
    )
    return lower ... upper
}

func workspaceLengthFieldPresentation(
    fromMeters meters: Double,
    preferredUnit: LengthDisplayUnit,
    policy: WorkspaceLengthFieldPresentationPolicy = .editing
) -> WorkspaceLengthFieldPresentation {
    let unit = preferredUnit.readableUnit(
        forMeters: meters,
        allowsKilometers: policy.allowsKilometers
    )
    let rawValue = unit.value(fromMeters: meters)
    let text = WorkspaceInspectorNumberText.string(from: rawValue)
    let value = WorkspaceInspectorNumberText.value(from: text) ?? rawValue
    return WorkspaceLengthFieldPresentation(
        meters: meters,
        value: value,
        unit: unit,
        text: text
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
                .lineLimit(1)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, WorkspaceInspectorLayout.sectionHeaderHorizontalPadding)
        .padding(.vertical, WorkspaceInspectorLayout.sectionHeaderVerticalPadding)
        .frame(maxWidth: .infinity, alignment: .leading)

        VStack(alignment: .leading, spacing: 0) {
            content()
        }
        .padding(.vertical, WorkspaceInspectorLayout.sectionContentVerticalPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .padding(.bottom, 10)
    .overlay(alignment: .bottom) { Divider() }
}

@MainActor
func inspectorControlRow<Content: View>(
    _ title: String,
    @ViewBuilder content: () -> Content
) -> some View {
    HStack(alignment: .center, spacing: inspectorRowSpacing) {
        Text(title)
            .font(.system(size: 11))
            .foregroundStyle(.secondary)
            .lineLimit(1)
            .help(title)
            .frame(width: inspectorLabelWidth, alignment: .leading)
        content()
            .font(.system(size: 11))
            .frame(maxWidth: .infinity, alignment: .trailing)
    }
    .padding(.horizontal, WorkspaceInspectorLayout.rowHorizontalPadding)
    .padding(.vertical, WorkspaceInspectorLayout.rowVerticalPadding)
    .frame(minHeight: WorkspaceInspectorLayout.rowMinimumHeight)
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
    axisField: Bool = false,
    onChange: @escaping (Double) -> Void,
    unitLabel: () -> String = { "" }
) -> some View {
    InspectorNumericInput(title: title, value: commonWorkspaceInspectorValue(values),
                          mapping: .number(range: sliderRange, unit: unitLabel()), onChange: onChange, axisField: axisField)
}

@MainActor
func workspaceScaleFactorControl(
    _ title: String,
    values: [Double],
    axisField: Bool = false,
    onChange: @escaping (Double) -> Void
) -> some View {
    let range = workspaceScaleFactorSliderRange(for: values)
    let scale = WorkspaceScaleFactorSliderScale(valueRange: range)
    return InspectorNumericInput(
        title: title, value: commonWorkspaceInspectorValue(values),
        mapping: InspectorNumericMapping(
            unit: "x", sliderRange: 0...1, sliderValue: scale.sliderValue,
            value: scale.value, format: WorkspaceInspectorNumberText.compact,
            parse: WorkspaceInspectorNumberText.value, editingFormat: { String($0) }),
        onChange: onChange, axisField: axisField)
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
    sliderMetersRange: ClosedRange<Double>,
    axisField: Bool = false,
    onChange: @escaping (Double) -> Void
) -> some View {
    let common = commonWorkspaceInspectorValue(values)
    let unit = common.map {
        workspaceLengthFieldPresentation(fromMeters: $0, preferredUnit: displayUnit).unit
    } ?? displayUnit
    let scale = WorkspaceLengthSliderScale(metersRange: sliderMetersRange)
    return InspectorNumericInput(
        title: title, value: common,
        mapping: InspectorNumericMapping(
            unit: unit.symbol, sliderRange: 0...1,
            sliderValue: scale.sliderValue, value: scale.meters,
            format: { WorkspaceInspectorNumberText.compact(unit.value(fromMeters: $0)) },
            parse: { workspaceLengthMeters(fromFieldText: $0, defaultUnit: unit) },
            editingFormat: { String(unit.value(fromMeters: $0)) }),
        onChange: onChange, axisField: axisField)
}
