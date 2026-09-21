import CoreGraphics

/// The widths the editor's split pane is laid out at.
///
/// The canvas column's minimum is a correctness bound rather than a
/// preference: the canvas header stands inside that column, and the header's
/// fixed seats are laid out at the width they declare, so a column narrower
/// than their sum would clip a seat that has no second copy anywhere else in
/// the workspace. `minimumCanvasWidth` is declared here and held above
/// `WorkspaceCanvasHeaderLayout.fixedSeatsWidth` by
/// `WorkspaceCanvasHeaderLayoutTests`, so adding a seat fails that test rather
/// than silently clipping the row.
enum WorkspaceEditorSplitLayout {
    static let minimumCanvasWidth: CGFloat = 600
    static let inspectorWidth: CGFloat = 320
    static let dividerDragStripWidth: CGFloat = 10

    /// The narrowest the document sidebar is laid out at.
    static let sidebarMinimumWidth: CGFloat = 220

    /// The window cannot be narrower than the three columns it holds. The
    /// split pane's own minimum only constrains a divider drag, so a window
    /// that allowed less would squeeze the canvas column past the bound the
    /// header depends on.
    static var minimumWindowWidth: CGFloat {
        sidebarMinimumWidth + minimumCanvasWidth + inspectorWidth
    }
}
