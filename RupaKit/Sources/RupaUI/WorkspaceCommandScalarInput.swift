import SwiftUI

/// A command dialog's typed plain number, such as a Bridge Curve's tension: D focuses it like a
/// distance, the value is the command's own setting and nothing is created while it is typed.
@MainActor
struct WorkspaceCommandScalarInput: View {
    var title: String
    var value: Binding<Double>
    var field: WorkspaceCommandDistanceField
    var focus: FocusState<WorkspaceCommandDistanceField?>.Binding
    var accessibilityIdentifier: String

    var body: some View {
        HStack(spacing: 4) {
            Text(title).foregroundStyle(.secondary)
            TextField(title, value: value, format: .number)
                .textFieldStyle(.roundedBorder)
                .frame(width: 64)
                .focused(focus, equals: field)
                .accessibilityIdentifier(accessibilityIdentifier)
        }
        .font(.caption)
    }
}
