import Foundation
import RupaViewportScene

/// What a selection rectangle does with one native answer.
///
/// A drag asks the mounted frame on every pointer move, so the two ways an
/// answer can be absent are different events and must not share a branch.
enum ViewportSelectionDragOutcome {
    /// The frame judged the rectangle. The answer is published as it stands.
    case publishes(ViewportSelectionDragTarget)
    /// No frame had judged the rectangle yet. Nothing is published and nothing
    /// is reported, so the last answered frame's preview stays on screen and
    /// the selection is unchanged.
    case retainsPreview(MeshSourcePresentationRenderError)
    /// The frame refused the rectangle. The preview is cleared and the failure
    /// is reported, because this is an outcome the operator must be able to
    /// see rather than a state that resolves itself.
    case refuses(any Error)
}

/// The single reader of a rectangle answer's failure classification.
///
/// `Viewport` is a SwiftUI `View` whose drag state is private, so the rule
/// lives here as a pure function and both call sites — the preview publisher
/// and the drag handler — dispatch on the same decision instead of each
/// forming its own.
enum ViewportSelectionDragFailurePolicy {
    static func outcome(
        for result: Result<ViewportSelectionDragTarget, any Error>
    ) -> ViewportSelectionDragOutcome {
        switch result {
        case let .success(target):
            return .publishes(target)
        case let .failure(error):
            guard let render = error as? MeshSourcePresentationRenderError,
                  render.code == .frameNotReady else {
                return .refuses(error)
            }
            return .retainsPreview(render)
        }
    }

    /// How a refusal reads in the log: the typed code the frame answered with,
    /// and the message that names the condition behind it.
    static func refusalDescription(_ error: any Error) -> String {
        guard let render = error as? MeshSourcePresentationRenderError else {
            return String(describing: error)
        }
        return "\(render.code.rawValue): \(render.message)"
    }
}
