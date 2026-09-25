import SwiftUI
import RupaCore

struct LoftSectionEditorFields: View {
    @Binding var controls: LoftSectionDraft
    let smooth: Bool
    var supportsCurveControls = true

    var body: some View {
        VStack(alignment: .leading) {
            TextField(text: $controls.startSampleIndex) {
                Text("Start sample index").fixedSize(horizontal: false, vertical: true)
            }
            .contentShape(Rectangle())
            .help("Leave blank for automatic. Zero-based source sample before reversal or trimming. Open curves must retain their start endpoint.")
            Picker("Section tangent", selection: $controls.tangentMode) {
                Text("Automatic").tag(LoftSectionSmoothTangentMode.automatic)
                Text("Zero derivative").tag(LoftSectionSmoothTangentMode.zero)
            }.disabled(!smooth).contentShape(Rectangle())
            TextField(text: $controls.tangentScale) {
                Text("Section tension").fixedSize(horizontal: false, vertical: true)
            }
            .disabled(!smooth || controls.tangentMode == .zero)
            .help("Leave blank to inherit the default tension. Applies to smooth connectors.")
            if supportsCurveControls {
                if controls.profileDirection != .automatic {
                    Button("Clear profile-only direction") { controls.profileDirection = .automatic }
                        .contentShape(Rectangle())
                }
                Toggle("Use curve interval", isOn: $controls.usesCurveInterval)
                    .contentShape(Rectangle())
                Toggle("Reverse curve direction", isOn: $controls.isReversed)
                    .contentShape(Rectangle())
                if controls.usesCurveInterval {
                    TextField("Start parameter", text: $controls.lowerParameter)
                    TextField("End parameter", text: $controls.upperParameter)
                    Text("Use the exact source curve's parameters, not display units.")
                        .font(.caption).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            } else {
                TextField(text: $controls.profileIndex) {
                    Text("Profile region index").fixedSize(horizontal: false, vertical: true)
                }
                .contentShape(Rectangle())
                .help("Zero-based closed region in the source sketch. Preview verifies that the selected region exists.")
                if controls.usesCurveInterval || controls.isReversed {
                    Button("Clear curve-only settings") {
                        controls.usesCurveInterval = false
                        controls.isReversed = false
                    }.contentShape(Rectangle())
                }
                Picker("Profile direction", selection: $controls.profileDirection) {
                    Text("Automatic").tag(LoftProfileDirection.automatic)
                    Text("Forward").tag(LoftProfileDirection.forward)
                    Text("Reversed").tag(LoftProfileDirection.reversed)
                }.contentShape(Rectangle())
            }
        }
    }
}
