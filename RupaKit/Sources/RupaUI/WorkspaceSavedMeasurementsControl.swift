import SwiftUI
import RupaCore

/// Lists the document's saved measurements in the Measure context panel.
///
/// Every saved measurement appears here, including one whose anchors no longer resolve: the
/// viewport draws only resolved measurements, so this control is where an unresolved one is
/// reported and where any of them can be deleted.
struct WorkspaceSavedMeasurementsControl: View {
    var resolutions: [MeasurementAnnotationResolver.Resolution]
    var onDelete: (MeasurementAnnotationID) -> Void

    private var unresolvedMessages: [String] {
        resolutions.compactMap { resolution in
            guard case .unresolved(let error) = resolution.outcome else {
                return nil
            }
            return error.message
        }
    }

    var body: some View {
        if !resolutions.isEmpty {
            Menu {
                ForEach(resolutions, id: \.measurementID) { resolution in
                    Button(role: .destructive) {
                        onDelete(resolution.measurementID)
                    } label: {
                        Label("Delete \(resolution.name)", systemImage: "trash")
                    }
                }
            } label: {
                Label("Saved \(resolutions.count)", systemImage: "ruler")
                    .font(.caption)
            }
            .menuStyle(.button)
            .fixedSize()
            .accessibilityIdentifier("WorkspaceMeasure.saved")
            let unresolved = unresolvedMessages
            if !unresolved.isEmpty {
                workspaceStatusChip(
                    "\(unresolved.count) unresolved",
                    systemImage: workspaceStatusSystemImage(for: .warning),
                    tint: workspaceStatusTint(for: .warning)
                )
                .help(unresolved.joined(separator: "\n"))
                .accessibilityIdentifier("WorkspaceMeasure.unresolved")
            }
        }
    }
}

#Preview("Saved measurements") {
    HStack {
        WorkspaceSavedMeasurementsControl(
            resolutions: [
                .init(
                    measurementID: MeasurementAnnotationID(),
                    name: "Distance 1",
                    kind: .distance,
                    outcome: .resolved([])
                ),
                .init(
                    measurementID: MeasurementAnnotationID(),
                    name: "Distance 2",
                    kind: .distance,
                    outcome: .unresolved(EditorError(
                        code: .referenceUnresolved,
                        message: "Measurement \"Distance 2\" anchor 1: The measured occurrence is no longer in the scene."
                    ))
                ),
            ],
            onDelete: { _ in }
        )
    }
    .padding()
}
