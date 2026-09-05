import SwiftUI
import RupaCore

struct FeatureHistoryRowPresentation: Equatable, Sendable {
    var title: String
    var inputNames: [String]
    var statusTitle: String

    init(
        feature: FeatureNode,
        index: Int,
        namesByID: [FeatureID: String]
    ) {
        title = feature.name ?? "Feature \(index + 1)"
        inputNames = feature.inputs.map { input in
            let name = namesByID[input.featureID] ?? input.featureID.description
            return "\(name) (\(input.role.rawValue))"
        }
        statusTitle = feature.isSuppressed ? "Suppressed" : "Active"
    }

    var inputSummary: String {
        inputNames.isEmpty ? "Inputs: None" : "Inputs: " + inputNames.joined(separator: ", ")
    }
}

func featureHistoryReorderCommand(
    orderedFeatures: [FeatureNode],
    visibleFeatureIDs: Set<FeatureID>?,
    movingFeatureID: FeatureID,
    offset: Int
) -> EditorCommand? {
    guard offset == -1 || offset == 1 else {
        return nil
    }
    if let visibleFeatureIDs,
       visibleFeatureIDs.contains(movingFeatureID) == false {
        return nil
    }
    guard let sourceIndex = orderedFeatures.firstIndex(where: { $0.id == movingFeatureID }) else {
        return nil
    }
    let destinationIndex = sourceIndex + offset
    guard orderedFeatures.indices.contains(destinationIndex) else {
        return nil
    }
    var order = orderedFeatures.map(\.id)
    order.swapAt(sourceIndex, destinationIndex)
    return .reorderFeatureGraph(featureIDs: order)
}

struct FeatureHistoryView: View {
    let orderedFeatures: [FeatureNode]
    let visibleFeatureIDs: Set<FeatureID>?
    let featureNamesByID: [FeatureID: String]
    let isBusy: Bool
    let onSelect: (FeatureID) -> Void
    let onPreview: (EditorCommand, String) -> Void

    init(
        orderedFeatures: [FeatureNode],
        visibleFeatureIDs: Set<FeatureID>? = nil,
        namesByID: [FeatureID: String] = [:],
        isBusy: Bool,
        onSelect: @escaping (FeatureID) -> Void,
        onPreview: @escaping (EditorCommand, String) -> Void
    ) {
        self.orderedFeatures = orderedFeatures
        self.visibleFeatureIDs = visibleFeatureIDs
        self.featureNamesByID = namesByID
        self.isBusy = isBusy
        self.onSelect = onSelect
        self.onPreview = onPreview
    }

    var body: some View {
        let namesByID = featureNamesByID.isEmpty
            ? Dictionary(
                uniqueKeysWithValues: orderedFeatures.enumerated().map { index, feature in
                    (feature.id, feature.name ?? "Feature \(index + 1)")
                }
            )
            : featureNamesByID
        let indicesByID = Dictionary(
            uniqueKeysWithValues: orderedFeatures.enumerated().map { index, feature in
                (feature.id, index)
            }
        )
        let visibleFeatures = visibleFeatureIDs.map { visibleIDs in
            orderedFeatures.filter { visibleIDs.contains($0.id) }
        } ?? orderedFeatures
        ForEach(Array(visibleFeatures.enumerated()), id: \.element.id) { visibleIndex, feature in
            let orderedIndex = indicesByID[feature.id] ?? visibleIndex
            let presentation = FeatureHistoryRowPresentation(
                feature: feature,
                index: orderedIndex,
                namesByID: namesByID
            )
            HStack(spacing: 8) {
                Button { onSelect(feature.id) } label: {
                    VStack(alignment: .leading, spacing: 3) {
                        Label(
                            presentation.title,
                            systemImage: feature.isSuppressed ? "pause.circle" : "cube.transparent"
                        )
                        .foregroundStyle(feature.isSuppressed ? .secondary : .primary)
                        Text(presentation.inputSummary)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }
                }
                .buttonStyle(.plain)
                .accessibilityValue(presentation.statusTitle)
                Spacer(minLength: 0)
                Text(presentation.statusTitle)
                    .font(.caption2)
                    .foregroundStyle(feature.isSuppressed ? .secondary : .tertiary)
                    .accessibilityIdentifier("FeatureHistory.\(feature.id).status")
                Menu {
                    Button(feature.isSuppressed ? "Unsuppress…" : "Suppress…") {
                        onPreview(
                            .setFeatureSuppression(
                                featureID: feature.id,
                                isSuppressed: !feature.isSuppressed
                            ),
                            feature.isSuppressed ? "Unsuppress Feature" : "Suppress Feature"
                        )
                    }
                    Button("Move Earlier…") { reorder(feature.id, offset: -1) }
                        .disabled(orderedIndex == orderedFeatures.startIndex)
                    Button("Move Later…") { reorder(feature.id, offset: 1) }
                        .disabled(orderedIndex == orderedFeatures.index(before: orderedFeatures.endIndex))
                } label: { Image(systemName: "ellipsis") }
                    .menuStyle(.borderlessButton)
                    .fixedSize()
                    .disabled(isBusy)
                    .accessibilityLabel("Actions for \(presentation.title)")
            }
            .help(
                feature.inputs.isEmpty
                    ? "Source feature"
                    : "Depends on \(feature.inputs.count) earlier feature(s)"
            )
        }
    }

    private func reorder(_ featureID: FeatureID, offset: Int) {
        guard let command = featureHistoryReorderCommand(
            orderedFeatures: orderedFeatures,
            visibleFeatureIDs: visibleFeatureIDs,
            movingFeatureID: featureID,
            offset: offset
        ) else {
            return
        }
        onPreview(command, "Reorder Feature History")
    }
}
