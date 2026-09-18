import SwiftUI

struct InspectorNumericInput: View {
    let title: String
    let value: Double?
    let mapping: InspectorNumericMapping
    let onChange: (Double) -> Void
    var axisField: Bool = false

    @Environment(\.inspectorInputSequencer) private var sequencer
    @State private var edit = InspectorNumericEdit()
    @State private var controlID = UUID()
    @State private var observer: Task<Void, Never>?
    @State private var pendingCompletion: (revision: Int, task: Task<Void, Never>?)?
    @State private var isDragging = false
    @FocusState private var isFocused: Bool

    private var activeMapping: InspectorNumericMapping { edit.mapping ?? mapping }

    var body: some View {
        Group {
            if axisField {
                numberField
            } else {
                inspectorControlRow(title) {
                    HStack(spacing: 4) {
                        numberField.frame(width: 62)
                        InspectorSlider(title: title,
                            value: Self.sliderBinding(edit: $edit, value: value, mapping: mapping, onChange: submit),
                            range: activeMapping.sliderRange, step: activeMapping.step,
                            valueDescription: (edit.value ?? value).map(activeMapping.format).map {
                                activeMapping.unit.isEmpty ? $0 : "\($0) \(activeMapping.unit)"
                            } ?? "Mixed") { editing in
                            isDragging = editing
                            if editing {
                                isFocused = false
                                edit.begin(mapping)
                            } else {
                                edit.end()
                            }
                        }
                    }
                }
            }
        }
        .onChange(of: isFocused) { _, focused in
            if focused { edit.begin(mapping) } else if !isDragging { edit.end() }
        }
        .onDisappear {
            observer?.cancel()
            observer = nil
            pendingCompletion = nil
        }
    }

    private var numberField: some View {
        HStack(spacing: 3) {
            if axisField { Text(title).foregroundStyle(.secondary) }
            TextField(title, text: Binding(
                get: {
                    edit.text ?? value.map(isFocused ? (activeMapping.editingFormat ?? activeMapping.format)
                        : activeMapping.format) ?? "Mixed"
                },
                set: { text in
                    if isFocused { edit.begin(mapping) }
                    if let value = edit.setText(text, mapping: mapping) { submit(value) }
                }))
                .textFieldStyle(.plain)
                .focused($isFocused)
                .onSubmit { isFocused = false }
                .foregroundStyle(.primary)
                .accessibilityLabel(title + (activeMapping.unit.isEmpty ? "" : " (\(activeMapping.unit))"))
        }
        .font(.system(size: 11).monospacedDigit())
        .padding(.horizontal, 6)
        .frame(maxWidth: .infinity, minHeight: 24, maxHeight: 24)
        .background(Color.primary.opacity(0.055), in: RoundedRectangle(cornerRadius: 5))
        .help(activeMapping.unit.isEmpty ? title : "\(title) (\(activeMapping.unit))")
    }

    /// Shared by the custom slider and non-foreground binding contract tests.
    static func sliderBinding(
        edit: Binding<InspectorNumericEdit>, value: Double?,
        mapping: InspectorNumericMapping, onChange: @escaping (Double) -> Void
    ) -> Binding<Double> {
        Binding(
            get: {
                let current = edit.wrappedValue
                return (current.mapping ?? mapping).sliderValue(current.value ?? value ?? 0)
            },
            set: { position in
                onChange(edit.wrappedValue.setSlider(position, mapping: mapping))
            })
    }

    private func submit(_ value: Double) {
        let revision = edit.submitted()
        InspectorInputSubmission.$controlID.withValue(controlID) { onChange(value) }
        pendingCompletion = (revision, sequencer?.currentCompletion)
        guard observer == nil else { return }
        observer = Task { @MainActor in
            while let pending = pendingCompletion {
                await pending.task?.value
                guard !Task.isCancelled else { return }
                edit.acknowledged(pending.revision)
                if pendingCompletion?.revision == pending.revision { pendingCompletion = nil }
            }
            observer = nil
        }
    }
}
