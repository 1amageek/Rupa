import RupaCore
import RupaKit

/// Checks and publishes a selection change against the workspace's latest published view.
///
/// A view value captures the snapshot it was built from, while a command's completion runs after
/// the workspace has published the command's result. Checking a change there against the captured
/// snapshot refuses the very targets the command made. The submitter takes no snapshot, so it
/// cannot check against a stale one.
@MainActor
struct WorkspaceSelectionSubmitter {
    typealias Update = @MainActor @Sendable (inout SelectionModel, DesignDocument) throws -> Void
    typealias Enqueue = @MainActor (
        @escaping @MainActor @Sendable () async throws -> ProjectViewSnapshot
    ) -> Task<ProjectViewSnapshot, Error>

    let workspace: ProjectWorkspace
    /// Runs one operation in the workspace's operation order.
    let enqueue: Enqueue

    /// Checks `update` against the latest published view now, so the caller learns at once whether
    /// it applies, then queues it; throws the refusal when it does not apply.
    @discardableResult
    func submit(
        _ update: @escaping Update,
        completion: @escaping @MainActor @Sendable (ProjectViewSnapshot) -> Void = { _ in }
    ) throws -> Task<ProjectViewSnapshot, Error> {
        let current = try latestView()
        var selection = current.selection
        try update(&selection, current.document.document)
        return queue(update, completion: completion)
    }

    /// Queues `update` to apply to whichever view is current when its turn comes.
    @discardableResult
    func queue(
        _ update: @escaping Update,
        completion: @escaping @MainActor @Sendable (ProjectViewSnapshot) -> Void = { _ in }
    ) -> Task<ProjectViewSnapshot, Error> {
        enqueue { [workspace] in
            guard let current = workspace.view else {
                throw Self.unavailable
            }
            var selection = current.selection
            try update(&selection, current.document.document)
            let published = try await workspace.applySelection(.replace(selection))
            completion(published)
            return published
        }
    }

    private func latestView() throws -> ProjectViewSnapshot {
        guard let view = workspace.view else {
            throw Self.unavailable
        }
        return view
    }

    private static var unavailable: ProjectWorkspaceActionError {
        ProjectWorkspaceActionError(
            code: .snapshotUnavailable,
            message: "The project workspace has no published view snapshot."
        )
    }
}
