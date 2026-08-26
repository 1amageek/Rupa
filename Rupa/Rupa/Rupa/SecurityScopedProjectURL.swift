import Foundation

@MainActor
final class SecurityScopedProjectURL {
    let url: URL
    private let didStartAccessing: Bool

    init(_ url: URL) {
        self.url = url.standardizedFileURL
        self.didStartAccessing = self.url.startAccessingSecurityScopedResource()
    }

    deinit {
        if didStartAccessing {
            url.stopAccessingSecurityScopedResource()
        }
    }
}
