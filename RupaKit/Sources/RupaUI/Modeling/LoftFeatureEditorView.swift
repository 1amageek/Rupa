import SwiftUI
import RupaCore

struct LoftFeatureEditorView: View {
    @State var draft: LoftFeatureDraft
    let namesByID: [FeatureID: String]
    let inputCandidates: [FeatureNode]
    let onCancel: () -> Void
    let onPreview: (EditorCommand) -> Void

    var body: some View {
        let command = Result(catching: { try draft.command() })
        VStack(alignment: .leading, spacing: 12) {
            Text("Edit \(draft.title)").font(.headline).fixedSize(horizontal: false, vertical: true)
            Form {
                Picker("Connectors", selection: $draft.source.options.surfaceMode) {
                    Text("Ruled").tag(LoftSurfaceMode.ruled)
                    Text("Smooth").tag(LoftSurfaceMode.smooth)
                }.contentShape(Rectangle())
                TextField(text: $draft.defaultTension) {
                    Text("Default section tension").fixedSize(horizontal: false, vertical: true)
                }
                .disabled(draft.source.options.surfaceMode != .smooth).contentShape(Rectangle())
                .help("Positive dimensionless scale inherited by sections with blank tension. Applies to smooth connectors.")
                Toggle("Closed section loop", isOn: $draft.source.options.closesSectionLoop)
                    .disabled(draft.source.options.resultKind != .sheet)
                    .contentShape(Rectangle())
                ForEach(draft.source.sections.indices, id: \.self) { index in
                    let section = draft.source.sections[index]
                    Section {
                        Text(namesByID[section.featureID] ?? "\(section.featureID)")
                            .fixedSize(horizontal: false, vertical: true)
                        LoftSectionEditorFields(controls: Binding(
                            get: { draft.controls[section.featureID] ?? LoftSectionDraft(section: section) },
                            set: { draft.controls[section.featureID] = $0 }),
                            smooth: draft.source.options.surfaceMode == .smooth,
                            supportsCurveControls: !section.section.isProfile)
                        Button("Move section earlier") { draft.source.sections.swapAt(index, index - 1) }
                            .disabled(index == 0).contentShape(Rectangle())
                        Button("Remove section") { draft.removeSection(section.featureID) }
                            .contentShape(Rectangle())
                    } header: {
                        Text("Section \(index + 1)")
                    }
                }
                Menu("Add section") {
                    ForEach(availableInputs, id: \.id) { candidate in
                        let name = namesByID[candidate.id] ?? "\(candidate.id)"
                        if candidate.outputs.contains(where: { $0.role == .profile }) {
                            Button("\(name) — Profile") {
                                draft.appendSection(.profile(ProfileReference(featureID: candidate.id)))
                            }.contentShape(Rectangle())
                        }
                        if draft.source.options.resultKind == .sheet,
                           candidate.outputs.contains(where: { $0.role == .curve }) {
                            Button("\(name) — Curve") {
                                draft.appendSection(.curve(CurveSectionReference(featureID: candidate.id)))
                            }.contentShape(Rectangle())
                        }
                    }
                }
                .disabled(!availableInputs.contains { candidate in
                    candidate.outputs.contains { $0.role == .profile || (draft.source.options.resultKind == .sheet && $0.role == .curve) }
                }).contentShape(Rectangle())
                Section("Guide curves") {
                    ForEach(draft.source.guides.indices, id: \.self) { index in
                        let guide = draft.source.guides[index]
                        Text(namesByID[guide.featureID] ?? "\(guide.featureID)")
                            .fixedSize(horizontal: false, vertical: true)
                        HStack {
                            Button("Move guide earlier") { draft.source.guides.swapAt(index, index - 1) }
                                .disabled(index == 0).contentShape(Rectangle())
                            Button("Remove guide") { draft.source.guides.remove(at: index) }
                                .contentShape(Rectangle())
                        }
                    }
                    let available = availableInputs.filter { $0.outputs.contains { $0.role == .curve } }
                    Menu("Add guide curve") {
                        ForEach(available, id: \.id) { candidate in
                            Button(namesByID[candidate.id] ?? "\(candidate.id)") {
                                draft.source.guides.append(LoftGuideReference(featureID: candidate.id))
                            }.contentShape(Rectangle())
                        }
                    }.disabled(available.isEmpty).contentShape(Rectangle())
                }
            }.formStyle(.grouped)
            if case .failure(let error) = command {
                Text(error.localizedDescription).foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
            }
            HStack {
                Button("Cancel", action: onCancel).contentShape(Rectangle())
                Spacer()
                Button("Preview") {
                    if case .success(let value) = command { onPreview(value) }
                }
                .disabled({ if case .failure = command { return true }; return false }())
                .contentShape(Rectangle())
            }
        }.padding().frame(minWidth: 380, minHeight: 400)
    }

    private var availableInputs: [FeatureNode] {
        inputCandidates.filter { candidate in
            !draft.source.sections.contains { $0.featureID == candidate.id }
                && !draft.source.guides.contains { $0.featureID == candidate.id }
        }
    }
}
