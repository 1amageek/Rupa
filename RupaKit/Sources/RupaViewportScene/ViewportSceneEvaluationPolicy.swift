/// Selects whether scene construction may evaluate a document itself.
///
/// A caller that owns evaluation lifetime outside `MainActor` selects
/// ``suppliedOnly`` so kernel evaluation can never re-enter that caller's
/// thread through scene construction.
public enum ViewportSceneEvaluationPolicy: Sendable, Hashable {
    /// Evaluate on the calling thread when no supplied evaluation matches the
    /// document. This is the policy for callers that hold no evaluation
    /// authority of their own.
    case evaluateOnDemand

    /// Project only a supplied evaluation that matches the document. When no
    /// supplied evaluation matches, the scene is built without evaluated
    /// geometry instead of evaluating on the calling thread.
    case suppliedOnly
}
