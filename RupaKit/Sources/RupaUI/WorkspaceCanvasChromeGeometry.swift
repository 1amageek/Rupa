import CoreGraphics
import RupaRendering

/// Every chrome rectangle the canvas overlay host has measured, reduced to the
/// values the workspace hands back to the viewport.
///
/// The host publishes one of these per settled layout, so the fitting insets
/// and control-context identity derived from them change once rather than once
/// per chrome. See `RupaUI/DESIGN.md`, "State, Ownership, and Lifecycle".
struct WorkspaceCanvasChromeGeometry: Equatable, Sendable {
    /// Normalized, ordered exclusion rectangles for every measured chrome.
    var exclusions: [ViewportCanvasOverlayExclusion]

    /// Height the bottom chrome reserves for the context panel.
    var contextPanelHeight: CGFloat

    static let empty = WorkspaceCanvasChromeGeometry(
        exclusions: [],
        contextPanelHeight: 0.0
    )

    init(
        exclusions: [ViewportCanvasOverlayExclusion],
        contextPanelHeight: CGFloat
    ) {
        self.exclusions = exclusions
        self.contextPanelHeight = contextPanelHeight
    }

    /// Derives both values from the rectangles as they were measured.
    ///
    /// The reserved height comes from the context panel's own rectangle rather
    /// than from the matching exclusion, whose edges are rounded outward and can
    /// therefore stand up to a point taller than the panel that produced it.
    init(chromeRects: [WorkspaceCanvasOverlayChromeID: CGRect]) {
        self.exclusions = WorkspaceCanvasOverlayGeometry.normalizedExclusions(chromeRects)
        self.contextPanelHeight = WorkspaceCanvasOverlayGeometry.normalizedHeight(
            chromeRects[.contextPanel]?.height ?? 0.0
        )
    }
}
