import Foundation

public enum ProjectAccessTarget: Equatable, Sendable {
    case liveProject(URL)
    case liveSession(UUID)
    case closedProject(input: URL, output: URL?)

    public func validated() throws -> ProjectAccessTarget {
        switch self {
        case .liveSession:
            return self
        case .liveProject(let url):
            try Self.validateProjectURL(url)
            return self
        case .closedProject(let input, let output):
            try Self.validateProjectURL(input)
            if let output {
                try Self.validateProjectURL(output)
            }
            return self
        }
    }

    private static func validateProjectURL(_ url: URL) throws {
        guard url.isFileURL, !url.path.isEmpty else {
            throw ProjectAccessError.invalidTarget(url)
        }
        guard url.pathExtension.lowercased() == "rupa" else {
            throw ProjectAccessError.unsupportedProjectFormat(url)
        }
    }
}
