import RupaCore
import SwiftUI

/// Which command dialog's distance D focuses.
enum WorkspaceCommandDistanceField: Hashable {
    /// Offset Planar Curve's distance, Slot's width or Offset Vertex's distance.
    case curveOffset
    case edgeOffset
    case regionOffset
    /// Fillet's or Chamfer's distance.
    case cornerTreatment
    /// A Bridge Curve's G1 tension, a plain number.
    case bridgeTension
    /// Deform Curve's N offset.
    case deformOffset
}

/// A command dialog's typed distance, in the display unit. The value it holds is the command's own
/// setting and nothing is created while it is typed; Return creates the command's result.
@MainActor
struct WorkspaceCommandDistanceInput: View {
    var title: String
    var meters: Binding<Double>
    var unit: LengthDisplayUnit
    var field: WorkspaceCommandDistanceField
    var focus: FocusState<WorkspaceCommandDistanceField?>.Binding
    var accessibilityIdentifier: String

    var body: some View {
        HStack(spacing: 4) {
            Text(title).foregroundStyle(.secondary)
            TextField(title, value: Binding(
                get: { unit.value(fromMeters: meters.wrappedValue) },
                set: { meters.wrappedValue = unit.meters(from: $0) }
            ), format: .number)
                .textFieldStyle(.roundedBorder)
                .frame(width: 64)
                .focused(focus, equals: field)
                .accessibilityIdentifier(accessibilityIdentifier)
            Text(unit.symbol).foregroundStyle(.secondary)
        }
        .font(.caption)
    }
}
