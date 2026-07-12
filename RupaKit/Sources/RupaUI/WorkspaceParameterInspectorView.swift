import RupaCore
import SwiftUI

struct WorkspaceParameterInspectorView: View {
    var state: WorkspaceParameterInspectorState
    var onRename: (String, String) -> Bool
    var onUpsert: (String, String, QuantityKind) -> Bool
    var onDelete: (String) -> Bool

    @State private var nameDrafts: [String: String] = [:]
    @State private var expressionDrafts: [String: String] = [:]
    @State private var newName = ""
    @State private var newExpression = ""
    @State private var newKindRawValue = QuantityKind.length.rawValue

    private let supportedKinds: [QuantityKind] = [.length, .angle, .scalar]

    init(
        state: WorkspaceParameterInspectorState,
        onRename: @escaping (String, String) -> Bool,
        onUpsert: @escaping (String, String, QuantityKind) -> Bool,
        onDelete: @escaping (String) -> Bool
    ) {
        self.state = state
        self.onRename = onRename
        self.onUpsert = onUpsert
        self.onDelete = onDelete
    }

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
        inspectorControlRow("Name") {
            HStack(spacing: 6) {
                TextField("Name", text: nameBinding(for: row))
                    .multilineTextAlignment(.trailing)
                    .frame(minWidth: inspectorControlWidth)
                Button {
                    applyName(row)
                } label: {
                    Image(systemName: "checkmark")
                        .frame(width: 14, height: 14)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .help("Rename parameter")
                .accessibilityIdentifier("WorkspaceParameter.\(row.name).rename")
            }
        }
        workspaceInspectorValueRow("Kind", row.kindTitle)
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
        workspaceInspectorValueRow("Used In", row.sourceUsageTitle)
        if row.hasDiagnostics {
            workspaceInspectorValueRow("Diagnostics", row.diagnosticTitle)
        }
        inspectorActionRow {
            Button(role: .destructive) {
                if onDelete(row.name) {
                    nameDrafts[row.id] = nil
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

    private func nameBinding(
        for row: WorkspaceParameterInspectorState.Row
    ) -> Binding<String> {
        Binding(
            get: {
                nameDrafts[row.id] ?? row.name
            },
            set: { value in
                nameDrafts[row.id] = value
            }
        )
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

    private func applyName(_ row: WorkspaceParameterInspectorState.Row) {
        let name = nameDrafts[row.id] ?? row.name
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmedName.isEmpty == false,
              trimmedName != row.name else {
            nameDrafts[row.id] = nil
            return
        }
        if onRename(row.name, trimmedName) {
            nameDrafts[row.id] = nil
        }
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
