import Foundation

/// An exclusive authority lease for canonical project files.
public struct ProjectFileAuthorityLease: Sendable {
    fileprivate let id: UUID
    let store: ProjectFileAuthorityLeaseStore
    fileprivate let paths: [URL]

    init(
        id: UUID,
        store: ProjectFileAuthorityLeaseStore,
        paths: [URL]
    ) {
        self.id = id
        self.store = store
        self.paths = paths
    }

    /// Revalidates the path and lock identities held by this lease.
    public func validate() async throws {
        try await store.validate(id: id)
    }

    /// Records the identity published by a successful atomic save.
    ///
    /// Atomic replacement may intentionally change the destination inode. The
    /// lease therefore closes the old source descriptor and binds to the
    /// newly published inode while retaining the same path lock.
    public func adoptPublished(_ path: URL) async throws {
        try await store.adoptPublished(path, leaseID: id)
    }

    /// Releases the lease. Releasing an already released lease is harmless.
    public func release() async {
        await store.release(id: id)
    }
}
