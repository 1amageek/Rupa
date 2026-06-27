import SwiftUI
import RupaCore

struct WorkspaceSketchEntityPointMoveControlsView: View {
    var title: String
    var target: SelectionTarget
    var handle: SketchEntityPointHandle
    var moveStepMeters: Double
    var accessibilityPrefix: String
    var onMovePoint: (SelectionTarget, SketchEntityPointHandle, Double, Double) -> Void

    var body: some View {
        axisControls(
            axisTitle: "X",
            negativeSystemImage: "arrow.left",
            positiveSystemImage: "arrow.right",
            negativeDelta: (-moveStepMeters, 0.0),
            positiveDelta: (moveStepMeters, 0.0)
        )
        axisControls(
            axisTitle: "Y",
            negativeSystemImage: "arrow.down",
            positiveSystemImage: "arrow.up",
            negativeDelta: (0.0, -moveStepMeters),
            positiveDelta: (0.0, moveStepMeters)
        )
    }

    private func axisControls(
        axisTitle: String,
        negativeSystemImage: String,
        positiveSystemImage: String,
        negativeDelta: (x: Double, y: Double),
        positiveDelta: (x: Double, y: Double)
    ) -> some View {
        inspectorControlRow("\(title) \(axisTitle)") {
            HStack(spacing: 6) {
                moveButton(
                    systemImage: negativeSystemImage,
                    help: "Move \(title.lowercased()) negative \(axisTitle)",
                    accessibilityIdentifier: "\(accessibilityPrefix).move\(axisTitle)Negative"
                ) {
                    onMovePoint(target, handle, negativeDelta.x, negativeDelta.y)
                }
                moveButton(
                    systemImage: positiveSystemImage,
                    help: "Move \(title.lowercased()) positive \(axisTitle)",
                    accessibilityIdentifier: "\(accessibilityPrefix).move\(axisTitle)Positive"
                ) {
                    onMovePoint(target, handle, positiveDelta.x, positiveDelta.y)
                }
            }
        }
    }

    private func moveButton(
        systemImage: String,
        help: String,
        accessibilityIdentifier: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .frame(width: 18, height: 18)
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
        .help(help)
        .accessibilityIdentifier(accessibilityIdentifier)
    }
}
