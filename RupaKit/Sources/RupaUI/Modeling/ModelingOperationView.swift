import SwiftUI
import RupaCore

struct ModelingOperationView: View {
    @Binding var draft: ModelingOperationDraft
    let document: DesignDocument
    let isBusy: Bool
    let hasMatchingPreview: Bool
    let errorMessage: String?
    let onUseSelection: () -> Void
    let onPreview: () -> Void
    let onApply: () -> Void
    let onCancel: () -> Void

    /// The reason the draft names no command for this document, or `nil` when
    /// it names one.
    ///
    /// `ModelingOperationDraft.command(in:)` is the one place that decides
    /// what a draft means, so the panel asks it rather than restating the
    /// preconditions. The answer is a function of the draft and the document
    /// read while the body is built, not an event, so it is displayed and not
    /// recorded. See `Modeling/DESIGN.md`.
    var planningRefusal: String? {
        switch Result(catching: { try draft.command(in: document) }) {
        case .success: nil
        case .failure(let error): error.localizedDescription
        }
    }

    var body: some View {
        // Planned once per body evaluation: `Preview` and the reason beside it
        // are the same answer, and planning twice would walk the operand
        // ancestors twice.
        let refusal = planningRefusal
        VStack(alignment: .leading, spacing: 12) {
            Text(draft.kind.rawValue).font(.headline)
            Form {
                TextField("Name", text: $draft.name)
                if ![.box, .cylinder, .sphere].contains(draft.kind) {
                    Section("Operands (source coordinates)") {
                        ForEach(draft.targets.indices, id: \.self) { index in
                            HStack {
                                Text(draft.operandTitle(at: index, in: document))
                                Spacer()
                                Button { draft.targets.swapAt(index, index - 1) } label: { Image(systemName: "arrow.up") }
                                    .disabled(index == 0)
                                    .accessibilityLabel("Move operand up")
                                Button { draft.targets.remove(at: index) } label: { Image(systemName: "minus.circle") }
                                    .accessibilityLabel("Remove operand")
                            }
                        }
                        Button("Use Current Selection", action: onUseSelection)
                    }
                }
                parameters
            }
            .disabled(isBusy)
            if let refusal {
                Text(refusal).foregroundStyle(.secondary).font(.callout).textSelection(.enabled)
                    .accessibilityIdentifier("Modeling.refusal")
            }
            if let errorMessage {
                Text(errorMessage).foregroundStyle(.red).font(.callout).textSelection(.enabled)
                    .accessibilityIdentifier("Modeling.error")
            }
            if isBusy { ProgressView("Evaluating…").controlSize(.small) }
            HStack {
                Button("Cancel", action: onCancel).keyboardShortcut(.cancelAction)
                Spacer()
                Button("Preview", action: onPreview).disabled(isBusy || refusal != nil)
                    .accessibilityIdentifier("Modeling.preview")
                Button("Apply", action: onApply).disabled(isBusy || !hasMatchingPreview)
                    .keyboardShortcut(.defaultAction)
                    .accessibilityIdentifier("Modeling.apply")
            }
        }
        .padding(16)
        .frame(minWidth: 320, idealWidth: 360)
        .accessibilityIdentifier("Modeling.operation")
    }

    @ViewBuilder private var parameters: some View {
        switch draft.kind {
        case .box:
            vectorFields("Origin", values: $draft.origin, unit: draft.unit.symbol)
            lengthField("Width X", text: $draft.width)
            lengthField("Width Y", text: $draft.height)
            lengthField("Depth Z", text: $draft.distance)
        case .cylinder, .sphere:
            vectorFields(draft.kind == .sphere ? "Center" : "Base center", values: $draft.origin, unit: draft.unit.symbol)
            lengthField("Radius", text: $draft.width)
            if draft.kind == .cylinder { lengthField("Depth", text: $draft.distance) }
        case .extrude:
            lengthField("Distance", text: $draft.distance)
            Toggle("Symmetric", isOn: $draft.symmetric)
        case .revolve:
            vectorFields("Axis origin", values: $draft.origin, unit: draft.unit.symbol)
            vectorFields("Axis direction", values: $draft.axis, unit: "")
            TextField("Angle (degrees)", text: $draft.angle)
        case .sweep:
            Text("Select the section first, optional guides next, and the path last.").font(.caption).foregroundStyle(.secondary)
        case .loft:
            Toggle("Sheet output", isOn: $draft.sheet)
            Toggle("Smooth connectors", isOn: $draft.smooth)
            Toggle("Closed section loop", isOn: $draft.closesSectionLoop)
        case .boolean:
            Picker("Operation", selection: $draft.booleanOperation) {
                Text("Union").tag(BooleanOperation.union)
                Text("Subtract").tag(BooleanOperation.difference)
                Text("Intersect").tag(BooleanOperation.intersect)
                Text("Slice").tag(BooleanOperation.slice)
            }
            Toggle("Keep tool bodies", isOn: $draft.keepTools)
        case .fillet:
            lengthField("Radius", text: $draft.distance)
            TextField("Segments", text: $draft.filletSegments)
        case .chamfer:
            lengthField("Distance", text: $draft.distance)
        }
    }

    private func lengthField(_ title: String, text: Binding<String>) -> some View {
        TextField("\(title) (\(draft.unit.symbol))", text: text)
    }

    private func vectorFields(_ title: String, values: Binding<[String]>, unit: String) -> some View {
        Section(title) {
            ForEach(0..<3) { index in
                TextField("\(["X", "Y", "Z"][index]) \(unit)", text: Binding(
                    get: { values.wrappedValue[index] },
                    set: { values.wrappedValue[index] = $0 }
                ))
            }
        }
    }
}
