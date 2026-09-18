import SwiftUI

struct InspectorVectorRow<Content: View>: View {
    let title: String
    @ViewBuilder var content: Content

    var body: some View {
        inspectorControlRow(title) {
            HStack(spacing: 4) { content }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(title)
    }
}
