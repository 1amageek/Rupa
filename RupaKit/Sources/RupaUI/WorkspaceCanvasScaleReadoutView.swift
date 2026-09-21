import RupaRendering
import SwiftUI

/// Observes high-frequency zoom updates only inside the scale readout.
struct WorkspaceCanvasScaleReadoutView: View {
    let camera: WorkspaceViewportCameraState
    let minorStep: ViewportProjectedGrid.ScaleReadout.Length?
    var isOverflow = false

    var body: some View {
        let readout = WorkspaceCanvasScaleReadout(minorStep: minorStep, zoom: camera.zoom)
        if isOverflow {
            workspaceValueRow("Scale", readout?.text ?? "Not measured",
                              accessibilityIdentifier: "WorkspaceScale.overflowReadout")
        } else if let readout {
            workspaceValuePill("Scale", readout.text)
                .help("Canvas Scale")
                .accessibilityElement(children: .ignore)
                .accessibilityIdentifier("WorkspaceScale.readout")
                .accessibilityLabel("Canvas Scale")
                .accessibilityValue(readout.accessibilityValue)
        }
    }
}
