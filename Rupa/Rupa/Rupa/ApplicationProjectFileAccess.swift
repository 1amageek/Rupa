import Foundation

/// Retains the App's security-scoped access to the current project file.
@MainActor
final class ApplicationProjectFileAccess {
    let access: any SecurityScopedProjectAccess
    let canonicalURL: URL

    var url: URL {
        access.url
    }

    init(access: any SecurityScopedProjectAccess) {
        self.access = access
        self.canonicalURL = Self.canonicalURL(access.url)
    }

    func owns(_ candidate: URL) -> Bool {
        canonicalURL == Self.canonicalURL(candidate)
    }

    private static func canonicalURL(_ url: URL) -> URL {
        url.standardizedFileURL
            .resolvingSymlinksInPath()
            .standardizedFileURL
    }
}
