import Foundation

/// The single owner of the transient/refusal split for a native frame query.
///
/// `MeshSourcePresentationRenderError.Code.frameNotReady` is the one code that
/// says nothing has judged the query yet, so a caller that can ask again
/// should. Every other code is an answer the caller must act on. Rectangle
/// selection and the affordance drag routes both read that classification, and
/// stating it once keeps them from each forming their own.
enum ViewportNativeQueryFailure {
    /// The typed error when `error` is the frame saying "not yet" rather than
    /// "no", and `nil` when it is an answer the caller must act on.
    static func transient(_ error: any Error) -> MeshSourcePresentationRenderError? {
        guard let render = error as? MeshSourcePresentationRenderError,
              render.code == .frameNotReady else {
            return nil
        }
        return render
    }

    /// Whether `error` is the frame saying "not yet" rather than "no".
    static func isTransient(_ error: any Error) -> Bool {
        transient(error) != nil
    }

    /// How a refusal reads in the log: the typed code the frame answered with,
    /// and the message that names the condition behind it.
    static func description(_ error: any Error) -> String {
        guard let render = error as? MeshSourcePresentationRenderError else {
            return String(describing: error)
        }
        return "\(render.code.rawValue): \(render.message)"
    }
}
