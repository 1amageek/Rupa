import SwiftUI

/// Compact slider shared by all Inspector numeric properties.
struct InspectorSlider: View {
    let title: String
    @Binding var value: Double
    let range: ClosedRange<Double>
    var step: Double? = nil
    let valueDescription: String
    let onEditingChanged: (Bool) -> Void

    @Environment(\.isEnabled) private var isEnabled
    @State private var grabOffset: CGFloat?
    @FocusState private var isFocused: Bool
    private let thumbWidth: CGFloat = 16

    var body: some View {
        GeometryReader { geometry in
            let travel = max(geometry.size.width - thumbWidth, 0)
            let span = range.upperBound - range.lowerBound
            let fraction = span > 0 ? min(max((value - range.lowerBound) / span, 0), 1) : 0
            let left = CGFloat(fraction) * travel
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 5).fill(Color.primary.opacity(0.07))
                RoundedRectangle(cornerRadius: 5)
                    .fill(Color.primary.opacity(isFocused ? 0.34 : 0.22))
                    .frame(width: thumbWidth).offset(x: left)
            }
            .contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance: 0)
                .onChanged { event in
                    guard isEnabled, travel > 0, span > 0 else { return }
                    if grabOffset == nil {
                        onEditingChanged(true)
                        isFocused = true
                        let start = event.startLocation.x
                        grabOffset = (left...left + thumbWidth).contains(start) ? start - left : thumbWidth / 2
                    }
                    value = Self.position(event.location.x - (grabOffset ?? thumbWidth / 2),
                                          travel: travel, range: range, step: step)
                }
                .onEnded { _ in finish() })
        }
        .frame(minWidth: 40, maxWidth: .infinity, minHeight: 24, maxHeight: 24)
        .opacity(isEnabled ? 1 : 0.4)
        .focusable(isEnabled)
        .focused($isFocused)
        .onKeyPress(.leftArrow) { adjust(-1); return .handled }
        .onKeyPress(.rightArrow) { adjust(1); return .handled }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(title)
        .accessibilityValue(valueDescription)
        .accessibilityAdjustableAction { direction in
            switch direction { case .increment: adjust(1); case .decrement: adjust(-1); @unknown default: break }
        }
        .onChange(of: isEnabled) { _, enabled in if !enabled { finish() } }
        .onDisappear { finish() }
    }

    static func position(_ offset: CGFloat, travel: CGFloat,
                         range: ClosedRange<Double>, step: Double?) -> Double {
        guard travel > 0, offset.isFinite else { return range.lowerBound }
        var value = range.lowerBound + Double(min(max(offset / travel, 0), 1)) * (range.upperBound - range.lowerBound)
        if let step, step > 0 {
            value = range.lowerBound + ((value - range.lowerBound) / step).rounded() * step
        }
        return min(max(value, range.lowerBound), range.upperBound)
    }

    private func adjust(_ direction: Double) {
        guard isEnabled, range.upperBound > range.lowerBound else { return }
        onEditingChanged(true)
        let increment = step ?? (range.upperBound - range.lowerBound) / 100
        value = Self.position(CGFloat(value + direction * increment - range.lowerBound),
                              travel: CGFloat(range.upperBound - range.lowerBound), range: range, step: step)
        onEditingChanged(false)
    }

    private func finish() {
        guard grabOffset != nil else { return }
        grabOffset = nil
        onEditingChanged(false)
    }
}
