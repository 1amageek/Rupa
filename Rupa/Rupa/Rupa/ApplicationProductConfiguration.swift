import Foundation
import RupaProjectAccessPlatform
import UniformTypeIdentifiers

enum ApplicationProductConfiguration {
    static let appGroupIdentifier = RupaAgentEndpointComposition.appGroupIdentifier
    nonisolated static let projectTypeIdentifier = "team.stamp.rupa.project"
    static let projectLeaseAcquisitionDuration: Duration = .seconds(5)

    static var projectContentType: UTType {
        UTType(
            exportedAs: projectTypeIdentifier,
            conformingTo: .data
        )
    }

    static func authorityDirectory(
        fileManager: FileManager = .default
    ) throws -> URL {
        try projectFileAuthorityDirectory(fileManager: fileManager)
            .deletingLastPathComponent()
    }

    static func projectFileAuthorityDirectory(
        fileManager: FileManager = .default
    ) throws -> URL {
        do {
            return try RupaProjectFileAuthorityComposition.projectFileDirectory(
                fileManager: fileManager
            )
        } catch let error as RupaProjectFileAuthorityComposition.ResolutionError {
            switch error {
            case .appGroupContainerUnavailable(let identifier):
                throw ApplicationAuthorityLeaseError.appGroupContainerUnavailable(
                    identifier
                )
            }
        }
    }
}
