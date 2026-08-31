import Foundation

/// Product-owned placement for cross-process project-file authority leases.
public enum RupaProjectFileAuthorityComposition {
    public enum ResolutionError: Error, Equatable, Sendable {
        case appGroupContainerUnavailable(String)
    }

    public static let authorityDirectoryName = "rupa-authority"
    public static let projectFileDirectoryName = "project-files"

    public static func projectFileDirectory(
        fileManager: FileManager = .default
    ) throws -> URL {
        guard let container = fileManager.containerURL(
            forSecurityApplicationGroupIdentifier:
                RupaAgentEndpointComposition.appGroupIdentifier
        ) else {
            throw ResolutionError.appGroupContainerUnavailable(
                RupaAgentEndpointComposition.appGroupIdentifier
            )
        }
        return container
            .appendingPathComponent(authorityDirectoryName, isDirectory: true)
            .appendingPathComponent(projectFileDirectoryName, isDirectory: true)
    }
}
