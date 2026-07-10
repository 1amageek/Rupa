import RupaCore
import RupaDomainFoundation
import SwiftUI

struct WorkspaceDomainCommandPanel: View {
    var command: WorkspaceCommandDescriptor
    var displayUnit: LengthDisplayUnit
    var generation: DocumentGeneration
    var execute: @MainActor (DomainCommandRequest) throws -> DomainExecutionResult

    @State private var draft: WorkspaceDomainCommandDraft
    @State private var isDryRun: Bool
    @State private var result: DomainExecutionResult?
    @State private var errorMessage: String?

    init(
        command: WorkspaceCommandDescriptor,
        displayUnit: LengthDisplayUnit,
        generation: DocumentGeneration,
        execute: @escaping @MainActor (DomainCommandRequest) throws -> DomainExecutionResult
    ) {
        self.command = command
        self.displayUnit = displayUnit
        self.generation = generation
        self.execute = execute
        self._draft = State(
            initialValue: WorkspaceDomainCommandDraft(
                descriptor: command.domainCapability
            )
        )
        self._isDryRun = State(initialValue: false)
        self._result = State(initialValue: nil)
        self._errorMessage = State(initialValue: nil)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            header

            if !command.domainCapability.parameters.isEmpty {
                ScrollView(.vertical) {
                    VStack(alignment: .leading, spacing: 12) {
                        ForEach(parameterGroups, id: \.self) { group in
                            parameterGroup(group)
                        }
                    }
                }
                .scrollIndicators(.automatic)
                .frame(maxHeight: 390)
            }

            Divider()

            executionControls

            if let result {
                resultSummary(result)
            } else if let errorMessage {
                Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("WorkspaceDomainCommand.error")
            }
        }
        .padding(10)
        .frame(width: 330, alignment: .topLeading)
        .accessibilityIdentifier("WorkspaceDomainCommand.panel")
        .onChange(of: generation) {
            if result?.generation != generation {
                invalidateResult()
            }
        }
        .onChange(of: isDryRun) {
            invalidateResult()
        }
    }

    private var header: some View {
        HStack(spacing: 8) {
            Image(systemName: command.systemImage)
                .font(.system(size: 14, weight: .semibold))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(command.mutatesDocument ? Color.accentColor : Color.secondary)
                .frame(width: 20, height: 20)

            VStack(alignment: .leading, spacing: 1) {
                Text(command.title)
                    .font(.subheadline.weight(.semibold))
                Text(command.domainCapability.summary)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var parameterGroups: [String] {
        var groups: [String] = []
        for parameter in command.domainCapability.parameters where !groups.contains(parameter.group) {
            groups.append(parameter.group)
        }
        return groups
    }

    @ViewBuilder
    private func parameterGroup(_ group: String) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(group.uppercased())
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)

            ForEach(parameters(in: group), id: \.id) { parameter in
                parameterRow(parameter)
            }
        }
    }

    private func parameters(in group: String) -> [DomainCommandParameterDescriptor] {
        command.domainCapability.parameters.filter { $0.group == group }
    }

    @ViewBuilder
    private func parameterRow(_ parameter: DomainCommandParameterDescriptor) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Text(parameter.label)
                    .font(.caption)
                    .foregroundStyle(Color.primary.opacity(0.82))
                    .lineLimit(1)

                Spacer(minLength: 4)

                if parameter.allowsNull || parameter.defaultValue == nil {
                    Toggle("Set Value", isOn: presenceBinding(for: parameter))
                        .toggleStyle(.switch)
                        .controlSize(.mini)
                        .labelsHidden()
                        .accessibilityLabel("Set \(parameter.label)")
                }
            }

            parameterControl(parameter)
                .disabled(!isParameterActive(parameter))
        }
        .help(parameter.summary)
        .accessibilityIdentifier("WorkspaceDomainCommand.parameter.\(parameter.id)")
    }

    @ViewBuilder
    private func parameterControl(_ parameter: DomainCommandParameterDescriptor) -> some View {
        switch parameter.kind {
        case .text:
            TextField(parameter.label, text: stringBinding(for: parameter))
                .textFieldStyle(.roundedBorder)
        case .boolean:
            Toggle(parameter.summary, isOn: boolBinding(for: parameter))
                .toggleStyle(.switch)
                .controlSize(.small)
                .labelsHidden()
                .frame(maxWidth: .infinity, alignment: .leading)
        case .integer:
            TextField(
                parameter.label,
                value: integerBinding(for: parameter),
                format: .number
            )
            .textFieldStyle(.roundedBorder)
        case .number:
            TextField(
                parameter.label,
                value: numberBinding(for: parameter),
                format: .number.precision(.significantDigits(1...12))
            )
            .textFieldStyle(.roundedBorder)
        case .length:
            HStack(spacing: 6) {
                TextField(
                    parameter.label,
                    value: lengthBinding(for: parameter),
                    format: .number.precision(.significantDigits(1...12))
                )
                .textFieldStyle(.roundedBorder)
                Text(displayUnit.symbol)
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .frame(minWidth: 20, alignment: .leading)
            }
        case .angle:
            HStack(spacing: 6) {
                TextField(
                    parameter.label,
                    value: numberBinding(for: parameter),
                    format: .number.precision(.significantDigits(1...8))
                )
                .textFieldStyle(.roundedBorder)
                Text("deg")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .frame(minWidth: 24, alignment: .leading)
            }
        case .choice:
            Picker(parameter.label, selection: stringBinding(for: parameter)) {
                ForEach(parameter.choices, id: \.value) { choice in
                    Text(choice.label)
                        .tag(choice.value)
                }
            }
            .labelsHidden()
            .pickerStyle(.menu)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var executionControls: some View {
        HStack(spacing: 8) {
            if command.supportsDryRun {
                Toggle("Dry Run", isOn: $isDryRun)
                    .toggleStyle(.switch)
                    .controlSize(.small)
                    .font(.caption)
            }

            Spacer(minLength: 8)

            Button {
                runCommand()
            } label: {
                Label("Run", systemImage: "play.fill")
                    .font(.caption.weight(.semibold))
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
            .accessibilityIdentifier("WorkspaceDomainCommand.run")
        }
    }

    private func resultSummary(_ result: DomainExecutionResult) -> some View {
        let errorCount = result.diagnostics.filter { $0.severity == .error }.count
        let warningCount = result.diagnostics.filter { $0.severity == .warning }.count
        return VStack(alignment: .leading, spacing: 3) {
            Label(
                result.message,
                systemImage: errorCount > 0 ? "xmark.circle.fill" : "checkmark.circle.fill"
            )
            .font(.caption.weight(.medium))
            .foregroundStyle(errorCount > 0 ? Color.red : Color.green)
            .fixedSize(horizontal: false, vertical: true)

            Text("Generation \(result.generation.value) | \(errorCount) errors | \(warningCount) warnings")
                .font(.caption2.monospacedDigit())
                .foregroundStyle(.secondary)

            if !result.validationRegions.isEmpty {
                Text("\(result.validationRegions.count) validation region(s)")
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(.secondary)

                ForEach(result.validationRegions) { region in
                    Text("\(region.kind.rawValue): \(region.id)")
                        .font(.caption2.monospaced())
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }

            if !result.diagnostics.isEmpty {
                ScrollView(.vertical) {
                    VStack(alignment: .leading, spacing: 3) {
                        ForEach(result.diagnostics) { diagnostic in
                            Text(diagnostic.message)
                                .font(.caption2)
                                .foregroundStyle(diagnosticColor(diagnostic.severity))
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
                .frame(maxHeight: 130)
            }
        }
        .accessibilityIdentifier("WorkspaceDomainCommand.result")
    }

    private func runCommand() {
        do {
            let request = try draft.request(
                descriptor: command.domainCapability,
                generation: generation,
                dryRun: isDryRun
            )
            result = try execute(request)
            errorMessage = nil
        } catch {
            result = nil
            errorMessage = error.localizedDescription
        }
    }

    private func isParameterActive(_ parameter: DomainCommandParameterDescriptor) -> Bool {
        draft.hasExplicitValue(for: parameter.id)
    }

    private func presenceBinding(
        for parameter: DomainCommandParameterDescriptor
    ) -> Binding<Bool> {
        Binding(
            get: { isParameterActive(parameter) },
            set: { isEnabled in
                if isEnabled {
                    setDraftValue(enabledValue(for: parameter), for: parameter)
                } else if parameter.allowsNull {
                    setDraftValue(.null, for: parameter)
                } else {
                    draft.unsetValue(for: parameter.id)
                    invalidateResult()
                }
            }
        )
    }

    private func enabledValue(
        for parameter: DomainCommandParameterDescriptor
    ) -> SemanticJSONValue {
        if let defaultValue = parameter.defaultValue, defaultValue != .null {
            return defaultValue
        }
        return defaultValue(for: parameter)
    }

    private func stringBinding(
        for parameter: DomainCommandParameterDescriptor
    ) -> Binding<String> {
        Binding(
            get: {
                guard case .string(let value) = draft.values[parameter.id] else {
                    return ""
                }
                return value
            },
            set: { setDraftValue(.string($0), for: parameter) }
        )
    }

    private func boolBinding(
        for parameter: DomainCommandParameterDescriptor
    ) -> Binding<Bool> {
        Binding(
            get: {
                guard case .bool(let value) = draft.values[parameter.id] else {
                    return false
                }
                return value
            },
            set: { setDraftValue(.bool($0), for: parameter) }
        )
    }

    private func integerBinding(
        for parameter: DomainCommandParameterDescriptor
    ) -> Binding<Int> {
        Binding(
            get: {
                guard case .number(let value) = draft.values[parameter.id] else {
                    return 0
                }
                return Int(exactly: value) ?? 0
            },
            set: { setDraftValue(.number(Double($0)), for: parameter) }
        )
    }

    private func numberBinding(
        for parameter: DomainCommandParameterDescriptor
    ) -> Binding<Double> {
        Binding(
            get: {
                guard case .number(let value) = draft.values[parameter.id] else {
                    return 0.0
                }
                return value
            },
            set: { setDraftValue(.number($0), for: parameter) }
        )
    }

    private func lengthBinding(
        for parameter: DomainCommandParameterDescriptor
    ) -> Binding<Double> {
        Binding(
            get: {
                guard case .number(let value) = draft.values[parameter.id] else {
                    return 0.0
                }
                return displayUnit.value(fromMeters: value)
            },
            set: { setDraftValue(.number(displayUnit.meters(from: $0)), for: parameter) }
        )
    }

    private func defaultValue(
        for parameter: DomainCommandParameterDescriptor
    ) -> SemanticJSONValue {
        switch parameter.kind {
        case .text:
            .string("")
        case .boolean:
            .bool(false)
        case .integer, .number, .length, .angle:
            .number(parameter.minimumValue ?? 0.0)
        case .choice:
            parameter.choices.first.map { .string($0.value) } ?? .string("")
        }
    }

    private func setDraftValue(
        _ value: SemanticJSONValue,
        for parameter: DomainCommandParameterDescriptor
    ) {
        draft.setValue(value, for: parameter.id)
        invalidateResult()
    }

    private func invalidateResult() {
        result = nil
        errorMessage = nil
    }

    private func diagnosticColor(_ severity: EditorDiagnostic.Severity) -> Color {
        switch severity {
        case .info:
            .secondary
        case .warning:
            .orange
        case .error:
            .red
        }
    }
}
