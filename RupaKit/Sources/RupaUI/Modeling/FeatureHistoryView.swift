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
    @State private var lengthDraft: FeatureLengthDraft?
    @State private var loftDraft: LoftFeatureDraft?
    let orderedFeatures: [FeatureNode]
    let parameters: ParameterTable
    let displayUnit: LengthDisplayUnit
    let visibleFeatureIDs: Set<FeatureID>?
    let featureNamesByID: [FeatureID: String]
    let isBusy: Bool
    let onSelect: (FeatureID) -> Void
    let onPreview: (EditorCommand, String) -> Void

    init(
        orderedFeatures: [FeatureNode],
        parameters: ParameterTable,
        displayUnit: LengthDisplayUnit,
        visibleFeatureIDs: Set<FeatureID>? = nil,
        namesByID: [FeatureID: String] = [:],
        isBusy: Bool,
        onSelect: @escaping (FeatureID) -> Void,
        onPreview: @escaping (EditorCommand, String) -> Void
    ) {
        self.orderedFeatures = orderedFeatures
        self.parameters = parameters
        self.displayUnit = displayUnit
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
                        Label {
                            Text(presentation.title)
                        } icon: {
                            WorkspaceSidebarSymbol(
                                systemName: feature.isSuppressed
                                    ? "pause.circle"
                                    : "cube.transparent"
                            )
                        }
                        .foregroundStyle(feature.isSuppressed ? .secondary : .primary)
                        Text(presentation.inputSummary)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .lineLimit(nil)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .contentShape(Rectangle())
                .accessibilityValue(presentation.statusTitle)
                Spacer(minLength: 0)
                Text(presentation.statusTitle)
                    .font(.caption2)
                    .foregroundStyle(feature.isSuppressed ? .secondary : .tertiary)
                    .accessibilityIdentifier("FeatureHistory.\(feature.id).status")
                Menu {
                    if case .loft = feature.operation {
                        Button("Edit Loft…") { loftDraft = LoftFeatureDraft(feature: feature) }
                            .contentShape(Rectangle())
                    }
                    if let draft = FeatureLengthDraft(feature: feature, parameters: parameters, unit: displayUnit) {
                        Button("Edit Dimension…") { lengthDraft = draft }
                            .contentShape(Rectangle())
                    }
                    Button(feature.isSuppressed ? "Unsuppress…" : "Suppress…") {
                        onPreview(
                            .setFeatureSuppression(
                                featureID: feature.id,
                                isSuppressed: !feature.isSuppressed
                            ),
                            feature.isSuppressed ? "Unsuppress Feature" : "Suppress Feature"
                        )
                    }
                    .contentShape(Rectangle())
                    Button("Move Earlier…") { reorder(feature.id, offset: -1) }
                        .contentShape(Rectangle())
                        .disabled(orderedIndex == orderedFeatures.startIndex)
                    Button("Move Later…") { reorder(feature.id, offset: 1) }
                        .contentShape(Rectangle())
                        .disabled(orderedIndex == orderedFeatures.index(before: orderedFeatures.endIndex))
                } label: {
                    WorkspaceSidebarSymbol(systemName: "ellipsis")
                        .contentShape(Rectangle())
                }
                    .contentShape(Rectangle())
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
        .sheet(item: $lengthDraft) { draft in
            FeatureLengthEditorView(draft: draft, parameters: parameters,
                onCancel: { lengthDraft = nil },
                onPreview: { command in
                    lengthDraft = nil
                    onPreview(command, "Edit \(draft.title)")
                })
        }
        .sheet(item: $loftDraft) { draft in
            LoftFeatureEditorView(draft: draft, namesByID: namesByID,
                inputCandidates: Array(orderedFeatures.prefix { $0.id != draft.id }
                    .filter { !$0.isSuppressed && $0.outputs.contains { $0.role == .curve || $0.role == .profile } }),
                onCancel: { loftDraft = nil },
                onPreview: { command in
                    loftDraft = nil
                    onPreview(command, "Edit \(draft.title)")
                })
        }
        .onChange(of: orderedFeatures) { _, _ in
            lengthDraft = nil
            loftDraft = nil
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
