import Foundation
import RupaProjectAccessPlatform
import UniformTypeIdentifiers

enum ApplicationProductConfiguration {
    nonisolated static let projectTypeIdentifier = "team.stamp.rupa.project"
    nonisolated static let access = RupaProductAccessConfiguration.current

    static var projectContentType: UTType {
        UTType(
            exportedAs: projectTypeIdentifier,
            conformingTo: .data
        )
    }

    nonisolated static func authorityDirectory(
        fileManager: FileManager = .default
    ) throws -> URL {
        guard let applicationSupport = fileManager.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first else {
            throw ApplicationAuthorityLeaseError
                .applicationSupportDirectoryUnavailable
        }
        return applicationSupport
            .appendingPathComponent(
                access.applicationBundleIdentifier,
                isDirectory: true
            )
            .appendingPathComponent("Authority", isDirectory: true)
    }

    nonisolated static func makeDiscoveryStore() -> KeychainAgentDiscoveryStore {
        access.makeDiscoveryStore()
    }
}
