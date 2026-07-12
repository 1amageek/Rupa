import Foundation

public struct GeometryCopyEvent: Codable, Equatable, Sendable {
    public var reason: GeometryCopyReason
    public var copiedBytes: Int

    public init(reason: GeometryCopyReason, copiedBytes: Int) {
        self.reason = reason
        self.copiedBytes = copiedBytes
    }
}
