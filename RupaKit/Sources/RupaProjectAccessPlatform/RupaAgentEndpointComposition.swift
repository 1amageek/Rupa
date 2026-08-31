import Foundation
import RupaAgentTransport

/// Product-owned endpoint placement for the process-lifetime Agent host.
/// Transport receives only the resulting endpoint value.
public enum RupaAgentEndpointComposition {
    public enum ResolutionError: Error, Equatable, Sendable {
        case appGroupContainerUnavailable(String)
        case invalidEndpoint(URL)
    }

    public static let appGroupIdentifier = "WWCKBW8CKN.team.stamp.rupa"
    public static let applicationBundleIdentifier = "team.stamp.Rupa"
    public static let endpointDirectoryName = "rupa-agent"
    public static let socketFileName = "rupa.sock"

    public static func productEndpoint(
        fileManager: FileManager = .default
    ) throws -> UnixSocketEndpoint {
        guard let container = fileManager.containerURL(
            forSecurityApplicationGroupIdentifier: appGroupIdentifier
        ) else {
            throw ResolutionError.appGroupContainerUnavailable(
                appGroupIdentifier
            )
        }
        let fileURL = container
            .appendingPathComponent(endpointDirectoryName, isDirectory: true)
            .appendingPathComponent(socketFileName, isDirectory: false)
        do {
            return try UnixSocketEndpoint(fileURL: fileURL)
        } catch {
            throw ResolutionError.invalidEndpoint(fileURL)
        }
    }
}
