import SwiftUI

/// The Command Palette (F): a search field narrowing the catalog as words are typed, arrows moving
/// the highlight, Return running the highlighted command and Escape closing it.
///
/// Its Return is scoped to the palette, so it never also reaches the workspace as a Return on the
/// canvas; the field's own key handlers take the arrows and Escape before the workspace does.
@MainActor
struct WorkspaceCommandPaletteView: View {
    var catalog: WorkspacePaletteCatalog = .standard
    var isAvailable: (WorkspacePaletteCatalog.Command) -> Bool
    var run: (WorkspacePaletteCatalog.Command) -> Void
    var close: () -> Void
    @State private var query = ""
    @State private var highlighted = 0
    @FocusState private var isSearchFocused: Bool

    var body: some View {
        let matches = catalog.matches(query)
        VStack(alignment: .leading, spacing: 6) {
            TextField("Command", text: $query)
                .textFieldStyle(.roundedBorder)
                .focused($isSearchFocused)
                .onSubmit { runHighlighted(in: matches) }
                .submitScope()
                .onKeyPress(.upArrow) {
                    highlighted = max(highlighted - 1, 0)
                    return .handled
                }
                .onKeyPress(.downArrow) {
                    highlighted = min(highlighted + 1, max(matches.count - 1, 0))
                    return .handled
                }
                .onKeyPress(.escape) {
                    close()
                    return .handled
                }
                .onChange(of: query) { _, _ in highlighted = 0 }
                .accessibilityIdentifier("WorkspaceCommandPalette.search")
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(Array(matches.enumerated()), id: \.element.id) { index, command in
                            row(command, isHighlighted: index == highlighted)
                                .id(command.id)
                        }
                    }
                }
                .frame(maxHeight: 260)
                .onChange(of: highlighted) { _, index in
                    if matches.indices.contains(index) { proxy.scrollTo(matches[index].id) }
                }
            }
            if matches.isEmpty {
                Text("No command matches.").font(.caption).foregroundStyle(.secondary)
            }
        }
        .padding(8)
        .frame(width: 320)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
        .onAppear { isSearchFocused = true }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("WorkspaceCommandPalette")
    }

    private func row(_ command: WorkspacePaletteCatalog.Command, isHighlighted: Bool) -> some View {
        let available = isAvailable(command)
        return Button {
            run(command)
        } label: {
            HStack {
                Text(command.title)
                Spacer()
                if let shortcut = command.shortcut {
                    Text(shortcut).foregroundStyle(.secondary).monospaced()
                }
            }
            .font(.callout)
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
            .background(isHighlighted ? Color.accentColor.opacity(0.25) : .clear, in: RoundedRectangle(cornerRadius: 4))
        }
        .buttonStyle(.plain)
        .disabled(!available)
        .opacity(available ? 1 : 0.45)
        .accessibilityIdentifier("WorkspaceCommandPalette.command.\(command.title)")
    }

    private func runHighlighted(in matches: [WorkspacePaletteCatalog.Command]) {
        guard matches.indices.contains(highlighted) else { return }
        let command = matches[highlighted]
        guard isAvailable(command) else { return }
        run(command)
    }
}
