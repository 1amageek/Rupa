import Foundation
import Observation
import RupaCore
import SwiftCAD

/// Holds display intent until the committed native frame replaces its predecessor.
@Observable
@MainActor
final class ViewportBodyCommitHandoff {
    private(set) var source: ViewportSourceIdentity?
    private(set) var mutation: Transform3D?
    private(set) var snapshotID: EvaluationSnapshotID?
    private var occurrenceIDs: [String] = []
    @ObservationIgnored private var token: UUID?

    var isPending: Bool { source != nil }

    func transforms(for source: ViewportSourceIdentity) -> [String: Transform3D] {
        guard self.source == source, let mutation else { return [:] }
        return Dictionary(uniqueKeysWithValues: occurrenceIDs.map { ($0, mutation) })
    }

    /// Called synchronously before releasing pointer ownership.
    @discardableResult
    func begin(
        source: ViewportSourceIdentity,
        snapshotID: EvaluationSnapshotID? = nil,
        mutation: Transform3D,
        occurrenceIDs: [String],
        commit: @escaping @MainActor () async throws -> ViewportSourceIdentity,
        onFailure: @escaping @MainActor (Error) -> Void
    ) -> Task<Void, Never> {
        precondition(!isPending)
        let token = UUID()
        self.token = token
        self.source = source
        self.snapshotID = snapshotID
        self.mutation = mutation
        self.occurrenceIDs = occurrenceIDs
        let task = Task { @MainActor [weak self] in
            do {
                let published = try await commit()
                guard let self, self.token == token else { return }
                // Publication is not a draw receipt. Keep the predecessor's
                // preview until observe() receives the applied successor frame.
                if published == source { self.reset() }
            } catch {
                guard let self, self.token == token else { return }
                self.reset()
                onFailure(error)
            }
        }
        return task
    }

    func observe(_ source: ViewportSourceIdentity) {
        guard let previous = self.source, previous != source else { return }
        reset()
    }

    /// Invalidates display ownership, not an already submitted transaction.
    func reset() {
        token = nil
        source = nil
        mutation = nil
        snapshotID = nil
        occurrenceIDs = []
    }
}
