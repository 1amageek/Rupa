import SwiftUI

/// The one place a canvas-header control is named.
///
/// The tooltip and the header's hover hint say the same words because they are handed the same
/// string here, and the hint is keyed by the identifier the control publishes, so a seat cannot
/// be named one way on hover and another way in its tooltip, and two seats that describe
/// themselves alike still cannot clear each other's hint.
struct WorkspaceHeaderControlName: ViewModifier {
    var title: String
    var identifier: String
    @Binding var hint: WorkspaceHoverHint

    func body(content: Content) -> some View {
        content
            .help(title)
            .accessibilityIdentifier(identifier)
            .onHover { isHovered in
                hint.report(title, from: identifier, isHovered: isHovered)
            }
    }
}

extension View {
    func workspaceHeaderControlName(
        _ title: String,
        identifier: String,
        hint: Binding<WorkspaceHoverHint>
    ) -> some View {
        modifier(WorkspaceHeaderControlName(title: title, identifier: identifier, hint: hint))
    }
}
