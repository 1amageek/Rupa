import Foundation

public enum UnixSocketEndpointError: Error, Equatable, Sendable {
    case invalidFileURL(URL)
}
