import AppKit
import RupaCore
import SwiftUI

/// Text's dialog: what to write, its font and its size; OK makes the curves.
@MainActor
struct WorkspaceTextDialog: View {
    @Binding var text: String
    @Binding var fontFamily: String
    /// The font size, in meters.
    @Binding var sizeMeters: Double
    var unit: LengthDisplayUnit
    var create: () -> Void
    var cancel: () -> Void

    var body: some View {
        Form {
            TextField("Text", text: $text)
                .accessibilityIdentifier("WorkspaceText.text")
            Picker("Font", selection: $fontFamily) {
                ForEach(NSFontManager.shared.availableFontFamilies, id: \.self) { family in
                    Text(family).tag(family)
                }
            }
            .accessibilityIdentifier("WorkspaceText.font")
            HStack {
                TextField("Size", value: Binding(
                    get: { unit.value(fromMeters: sizeMeters) },
                    set: { sizeMeters = unit.meters(from: $0) }
                ), format: .number)
                Text(unit.symbol).foregroundStyle(.secondary)
            }
            .accessibilityIdentifier("WorkspaceText.size")
            HStack {
                Spacer()
                Button("Cancel", action: cancel)
                    .keyboardShortcut(.cancelAction)
                Button("OK", action: create)
                    .keyboardShortcut(.defaultAction)
                    .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding()
        .frame(width: 360)
    }
}
