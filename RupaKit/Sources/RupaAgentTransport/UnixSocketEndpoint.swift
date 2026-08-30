import Foundation

public struct UnixSocketEndpoint: Equatable, Sendable {
    public let fileURL: URL

    public init(fileURL: URL) throws {
        guard fileURL.isFileURL, !fileURL.path.isEmpty else {
            throw UnixSocketEndpointError.invalidFileURL(fileURL)
        }
        self.fileURL = fileURL.standardizedFileURL
    }

    public var path: String {
        fileURL.path
    }
}
