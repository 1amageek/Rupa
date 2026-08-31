import Foundation
import RupaProjectAccessPlatform

/// Pairs Powerbox access with the cross-process lease for one project path.
@MainActor
final class ApplicationProjectFileAuthority {
    let access: any SecurityScopedProjectAccess
    let lease: ProjectFileAuthorityLease
    let canonicalURL: URL

    var url: URL {
        access.url
    }

    init(
        access: any SecurityScopedProjectAccess,
        lease: ProjectFileAuthorityLease
    ) {
        self.access = access
        self.lease = lease
        self.canonicalURL = Self.canonicalURL(access.url)
    }

    func owns(_ candidate: URL) -> Bool {
        canonicalURL == Self.canonicalURL(candidate)
    }

    func validate() async throws {
        try await lease.validate()
    }

    func adoptPublished(_ destination: URL) async throws {
        try await lease.adoptPublished(destination)
    }

    func release() async {
        await lease.release()
    }

    private static func canonicalURL(_ url: URL) -> URL {
        url.standardizedFileURL
            .resolvingSymlinksInPath()
            .standardizedFileURL
    }
}
