import SwiftUI
import RupaCore

struct FeatureHistoryView: View {
    let features: [FeatureNode]
    let isBusy: Bool
    let onSelect: (FeatureID) -> Void
    let onPreview: (EditorCommand, String) -> Void

    var body: some View {
        ForEach(Array(features.enumerated()), id: \.element.id) { index, feature in
            HStack(spacing: 8) {
                Button { onSelect(feature.id) } label: {
                    Label(feature.name ?? "Feature \(index + 1)", systemImage: feature.isSuppressed ? "pause.circle" : "cube.transparent")
                        .foregroundStyle(feature.isSuppressed ? .secondary : .primary)
                }.buttonStyle(.plain)
                Spacer(minLength: 0)
                Menu {
                    Button(feature.isSuppressed ? "Unsuppress…" : "Suppress…") {
                        onPreview(.setFeatureSuppression(featureID: feature.id, isSuppressed: !feature.isSuppressed), feature.isSuppressed ? "Unsuppress Feature" : "Suppress Feature")
                    }
                    Button("Move Earlier…") { reorder(index, to: index - 1) }.disabled(index == 0)
                    Button("Move Later…") { reorder(index, to: index + 1) }.disabled(index == features.count - 1)
                } label: { Image(systemName: "ellipsis") }
                    .menuStyle(.borderlessButton)
                    .fixedSize()
                    .disabled(isBusy)
                    .accessibilityLabel("Actions for \(feature.name ?? "feature")")
            }
            .help(feature.inputs.isEmpty ? "Source feature" : "Depends on \(feature.inputs.count) earlier feature(s)")
        }
    }

    private func reorder(_ index: Int, to destination: Int) {
        guard features.indices.contains(destination) else { return }
        var order = features.map(\.id)
        order.swapAt(index, destination)
        onPreview(.reorderFeatureGraph(featureIDs: order), "Reorder Feature History")
    }
}
