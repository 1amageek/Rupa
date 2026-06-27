import SwiftUI

struct WorkspaceInspectorTextSectionView: View {
    var section: WorkspaceInspectorTextSection

    var body: some View {
        inspectorSection(section.title) {
            ForEach(Array(section.rows.enumerated()), id: \.offset) { _, row in
                workspaceInspectorValueRow(row.title, row.value)
            }
        }
    }
}
