import RupaCore
import SwiftUI

struct WorkspaceParameterInspectorView: View {
    var state: WorkspaceParameterInspectorState
    var onUpsert: (String, String, QuantityKind) -> Bool
    var onDelete: (String) -> Bool

    @State private var expressionDrafts: [String: String] = [:]
    @State private var newName = ""
    @State private var newExpression = ""
    @State private var newKindRawValue = QuantityKind.length.rawValue

    private let supportedKinds: [QuantityKind] = [.length, .angle, .scalar]

    var body: some View {
        inspectorSection("Parameters") {
            workspaceInspectorValueRow("Count", state.summaryTitle)
            if state.hasDiagnostics {
                workspaceInspectorValueRow("Diagnostics", state.diagnosticTitle)
            }
            if state.rows.isEmpty {
                workspaceInspectorValueRow("Parameters", "None")
            } else {
                ForEach(state.rows) { row in
                    parameterRows(row)
                }
            }
            newParameterRows
        }
    }

    @ViewBuilder
    private func parameterRows(_ row: WorkspaceParameterInspectorState.Row) -> some View {
        workspaceInspectorValueRow(row.name, row.kindTitle)
        workspaceInspectorValueRow("Resolved", row.resolvedTitle)
        inspectorControlRow("Expression") {
            HStack(spacing: 6) {
                TextField("Expression", text: expressionBinding(for: row))
                    .multilineTextAlignment(.trailing)
                    .frame(minWidth: inspectorControlWidth)
                Button {
                    applyExpression(row)
                } label: {
                    Image(systemName: "checkmark")
                        .frame(width: 14, height: 14)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .help("Apply parameter expression")
                .accessibilityIdentifier("WorkspaceParameter.\(row.name).apply")
            }
        }
        workspaceInspectorValueRow("Uses", row.dependencyTitle)
        workspaceInspectorValueRow("Used By", row.dependentTitle)
        if row.hasDiagnostics {
            workspaceInspectorValueRow("Diagnostics", row.diagnosticTitle)
        }
        inspectorActionRow {
            Button(role: .destructive) {
                if onDelete(row.name) {
                    expressionDrafts[row.id] = nil
                }
            } label: {
                Label("Delete", systemImage: "trash")
            }
            .controlSize(.small)
            .accessibilityIdentifier("WorkspaceParameter.\(row.name).delete")
        }
    }

    private var newParameterRows: some View {
        Group {
            inspectorControlRow("New Name") {
                TextField("Name", text: $newName)
                    .multilineTextAlignment(.trailing)
                    .frame(minWidth: inspectorControlWidth)
                    .accessibilityIdentifier("WorkspaceParameter.new.name")
            }
            inspectorControlRow("New Kind") {
                Picker("", selection: $newKindRawValue) {
                    ForEach(supportedKinds, id: \.rawValue) { kind in
                        Text(kindTitle(kind))
                            .tag(kind.rawValue)
                    }
                }
                .labelsHidden()
                .controlSize(.small)
                .frame(minWidth: inspectorControlWidth)
                .accessibilityIdentifier("WorkspaceParameter.new.kind")
            }
            inspectorControlRow("New Expr") {
                TextField("Expression", text: $newExpression)
                    .multilineTextAlignment(.trailing)
                    .frame(minWidth: inspectorControlWidth)
                    .accessibilityIdentifier("WorkspaceParameter.new.expression")
            }
            inspectorActionRow {
                Button {
                    applyNewParameter()
                } label: {
                    Label("Add", systemImage: "plus")
                }
                .disabled(newName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    || newExpression.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                .controlSize(.small)
                .accessibilityIdentifier("WorkspaceParameter.new.add")
            }
        }
    }

    private func expressionBinding(
        for row: WorkspaceParameterInspectorState.Row
    ) -> Binding<String> {
        Binding(
            get: {
                expressionDrafts[row.id] ?? row.expression
            },
            set: { value in
                expressionDrafts[row.id] = value
            }
        )
    }

    private func applyExpression(_ row: WorkspaceParameterInspectorState.Row) {
        let expression = expressionDrafts[row.id] ?? row.expression
        guard expression.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false else {
            return
        }
        if onUpsert(row.name, expression, row.kind) {
            expressionDrafts[row.id] = nil
        }
    }

    private func applyNewParameter() {
        let trimmedName = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedExpression = newExpression.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmedName.isEmpty == false,
              trimmedExpression.isEmpty == false else {
            return
        }
        if onUpsert(trimmedName, trimmedExpression, kind(rawValue: newKindRawValue)) {
            newName = ""
            newExpression = ""
            newKindRawValue = QuantityKind.length.rawValue
        }
    }

    private func kindTitle(_ kind: QuantityKind) -> String {
        switch kind {
        case .length:
            "Length"
        case .angle:
            "Angle"
        case .scalar:
            "Scalar"
        }
    }

    private func kind(rawValue: String) -> QuantityKind {
        supportedKinds.first { $0.rawValue == rawValue } ?? .length
    }
}
