import Foundation
import UniformTypeIdentifiers

enum ApplicationProductConfiguration {
    static let appGroupIdentifier = "WWCKBW8CKN.team.stamp.rupa"
    nonisolated static let projectTypeIdentifier = "team.stamp.rupa.project"
    static let authorityDirectoryName = "rupa-authority"

    static var projectContentType: UTType {
        UTType(
            exportedAs: projectTypeIdentifier,
            conformingTo: .data
        )
    }

    static func authorityDirectory(
        fileManager: FileManager = .default
    ) throws -> URL {
        guard let container = fileManager.containerURL(
            forSecurityApplicationGroupIdentifier: appGroupIdentifier
        ) else {
            throw ApplicationAuthorityLeaseError.appGroupContainerUnavailable(
                appGroupIdentifier
            )
        }
        return container.appendingPathComponent(
            authorityDirectoryName,
            isDirectory: true
        )
    }
}
