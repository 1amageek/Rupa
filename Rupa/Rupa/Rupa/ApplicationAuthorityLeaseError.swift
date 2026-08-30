import Foundation

enum ApplicationAuthorityLeaseError: Error, Equatable, LocalizedError, Sendable {
    case appGroupContainerUnavailable(String)
    case directoryPreparationFailed(URL, message: String)
    case lockFileOpenFailed(URL, errorNumber: Int32)
    case lockFilePermissionFailed(URL, errorNumber: Int32)
    case alreadyRunning(URL)

    var errorDescription: String? {
        switch self {
        case .appGroupContainerUnavailable(let identifier):
            "The Rupa App Group container is unavailable: \(identifier)."
        case .directoryPreparationFailed(let url, let message):
            "The Rupa authority directory could not be prepared at \(url.path): \(message)"
        case .lockFileOpenFailed(let url, let errorNumber):
            "The Rupa authority lock could not be opened at \(url.path) (errno \(errorNumber))."
        case .lockFilePermissionFailed(let url, let errorNumber):
            "The Rupa authority lock permissions could not be set at \(url.path) (errno \(errorNumber))."
        case .alreadyRunning:
            "Another Rupa application process already owns the project authority."
        }
    }
}
