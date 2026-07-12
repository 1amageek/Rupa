import RupaCore
import RupaDomainFoundation
import SwiftUI

struct WorkspaceDomainCommandRow: View {
    var command: WorkspaceCommandDescriptor
    var displayUnit: LengthDisplayUnit
    var generation: DocumentGeneration
    var execute: @MainActor (DomainCommandRequest) throws -> DomainExecutionResult

    @State private var isPresented = false

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
    }

    var body: some View {
        Button {
            isPresented = true
        } label: {
            HStack(spacing: 7) {
                Image(systemName: command.systemImage)
                    .font(.system(size: 12, weight: .semibold))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(command.mutatesDocument ? Color.accentColor : Color.secondary)
                    .frame(width: 18, height: 18)

                VStack(alignment: .leading, spacing: 1) {
                    Text(command.title)
                        .font(.caption.weight(.medium))
                        .foregroundStyle(Color.primary.opacity(0.82))
                        .lineLimit(1)
                    Text(command.subtitle)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Spacer(minLength: 4)

                if command.supportsDryRun {
                    Image(systemName: "eye")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(Color.secondary)
                        .accessibilityLabel("Supports Dry Run")
                }

                Image(systemName: "chevron.right")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(Color.secondary.opacity(0.72))
            }
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 7)
        .frame(maxWidth: .infinity, minHeight: 30, alignment: .leading)
        .background {
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(Color.primary.opacity(0.06))
        }
        .help(command.failureMode)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(command.title)
        .accessibilityValue(accessibilityValue)
        .accessibilityIdentifier("WorkspaceDomainCommand.\(command.id)")
        .popover(isPresented: $isPresented, arrowEdge: .trailing) {
            WorkspaceDomainCommandPanel(
                command: command,
                displayUnit: displayUnit,
                generation: generation,
                execute: execute
            )
        }
    }

    private var accessibilityValue: String {
        let mutationTitle = command.mutatesDocument ? "Mutating" : "Read Only"
        let dryRunTitle = command.supportsDryRun ? "Dry Run Supported" : "No Dry Run"
        return "\(command.subtitle), \(mutationTitle), \(dryRunTitle), targets \(command.targetSummary)"
    }
}
