import Foundation

@MainActor
protocol SecurityScopedProjectAccessOpening {
    func open(_ url: URL) -> any SecurityScopedProjectAccess
}
