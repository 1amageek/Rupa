import Foundation
import Observation
import SwiftCAD

/// Holds display intent across the asynchronous source-publication boundary.
@Observable
@MainActor
final class ViewportBodyCommitHandoff {
    private(set) var source: ViewportSourceIdentity?
    private(set) var mutation: Transform3D?
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
        mutation: Transform3D,
        occurrenceIDs: [String],
        commit: @escaping @MainActor () async throws -> ViewportSourceIdentity,
        onFailure: @escaping @MainActor (Error) -> Void
    ) -> Task<Void, Never> {
        precondition(!isPending)
        let token = UUID()
        self.token = token
        self.source = source
        self.mutation = mutation
        self.occurrenceIDs = occurrenceIDs
        let task = Task { @MainActor [weak self] in
            do {
                let published = try await commit()
                guard let self, self.token == token else { return }
                // A new publication may not have reached SwiftUI yet. Retain
                // its predecessor's preview until observe() sees that change.
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
        occurrenceIDs = []
    }
}
