import Foundation

/// Failures specific to resolving a live App-owned project.
public enum LiveProjectAccessError: Error, Equatable, Sendable {
    case applicationUnavailable(bundleIdentifier: String)
    case applicationLaunchFailed(
        bundleIdentifier: String,
        projectURL: URL,
        errorDomain: String,
        errorCode: Int,
        message: String
    )
    case dirtyProjectConflict(URL)
    case multipleMatchingSessions(URL)
    case invalidSessionPath(String)
}

extension LiveProjectAccessError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .applicationUnavailable(let bundleIdentifier):
            "The Rupa application is unavailable for bundle identifier \(bundleIdentifier)."
        case .applicationLaunchFailed(
            let bundleIdentifier,
            let projectURL,
            let errorDomain,
            let errorCode,
            let message
        ):
            "The Rupa application \(bundleIdentifier) could not open \(projectURL.path): "
                + "\(errorDomain) \(errorCode): \(message)"
        case .dirtyProjectConflict(let url):
            "A different dirty project is already open; refusing to replace it: \(url.path)."
        case .multipleMatchingSessions(let url):
            "Multiple live sessions matched the canonical project path: \(url.path)."
        case .invalidSessionPath(let path):
            "The live session reported an invalid project path: \(path)."
        }
    }
}
