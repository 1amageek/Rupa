import Foundation

public struct GeometryCopyEvent: Codable, Equatable, Sendable {
    /// The operation that required ownership of copied source bytes.
    public let reason: GeometryCopyReason

    /// Element payload bytes attributed to the operation's required copy.
    /// Storage metadata, spare capacity, and zero-copy borrows are not included.
    public let copiedBytes: UInt64

    public init(reason: GeometryCopyReason, copiedBytes: UInt64) {
        self.reason = reason
        self.copiedBytes = copiedBytes
    }
}
