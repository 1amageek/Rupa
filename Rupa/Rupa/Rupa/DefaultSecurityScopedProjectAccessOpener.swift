import Foundation

@MainActor
struct DefaultSecurityScopedProjectAccessOpener: SecurityScopedProjectAccessOpening {
    func open(_ url: URL) -> any SecurityScopedProjectAccess {
        SecurityScopedProjectURL(url)
    }
}
