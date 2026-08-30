import Foundation

@MainActor
protocol SecurityScopedProjectAccess: AnyObject {
    var url: URL { get }
}

extension SecurityScopedProjectURL: SecurityScopedProjectAccess {}
