/// The one description the pointer has earned, shown in the canvas header.
///
/// A row of icons says nothing about what the icons are, and the system tooltip takes a pause
/// long enough that it may as well not exist. Hovering a header control writes its description
/// here the moment the pointer arrives.
///
/// Hover events between neighbouring controls arrive in no promised order -- the next control's
/// entry can precede the last one's exit -- so an exit clears only the hint that control itself
/// wrote, and a stale exit cannot erase a newer neighbour's. The control is named by the
/// accessibility identifier it already publishes, so two controls that describe themselves the
/// same way still cannot clear each other.
struct WorkspaceHoverHint: Equatable {
    private(set) var controlIdentifier: String?
    private(set) var text: String?

    mutating func report(_ text: String, from controlIdentifier: String, isHovered: Bool) {
        if isHovered {
            self.controlIdentifier = controlIdentifier
            self.text = text
        } else if self.controlIdentifier == controlIdentifier {
            self.controlIdentifier = nil
            self.text = nil
        }
    }
}
