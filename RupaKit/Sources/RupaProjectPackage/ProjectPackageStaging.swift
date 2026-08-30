import Foundation

/// Owns the temporary archive URL and, on Darwin, its item-replacement directory.
/// The package store keeps this value only for one synchronous save operation.
struct ProjectPackageStaging: Sendable {
    let packageURL: URL
    let directoryURL: URL?

    init(packageURL: URL, directoryURL: URL? = nil) {
        self.packageURL = packageURL
        self.directoryURL = directoryURL
    }
}
