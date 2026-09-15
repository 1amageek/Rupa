import CoreGraphics
import Foundation

/// The chrome rectangles the canvas overlay host has been handed, and the
/// publication that will hand them onward.
///
/// These are layout output rather than view state: they describe a layout that
/// has already run, and no view renders from them until the host has published
/// them. Holding them in a reference the host's body never reads keeps that
/// ownership explicit, so the only value the view graph sees is the published
/// one. See `RupaUI/DESIGN.md`, "State, Ownership, and Lifecycle".
@MainActor
final class WorkspaceCanvasChromeRectStore {
    /// Every chrome rectangle measured so far, in the overlay coordinate space.
    var rects: [WorkspaceCanvasOverlayChromeID: CGRect] = [:]

    /// The publication waiting to hand the current rectangles to the workspace.
    var publication: Task<Void, Never>?

    /// The host creates the store where it declares its state, outside the
    /// MainActor, so construction carries no isolation of its own.
    nonisolated init() {}
}
