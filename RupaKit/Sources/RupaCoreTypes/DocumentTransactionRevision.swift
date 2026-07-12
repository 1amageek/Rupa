import Foundation

public struct DocumentTransactionRevision: Codable, Comparable, Hashable, Sendable {
    public var value: UInt64

    public init(_ value: UInt64 = 0) {
        self.value = value
    }

    public func advanced() throws -> DocumentTransactionRevision {
        guard value < UInt64.max else {
            throw EditorError(
                code: .commandFailed,
                message: "Document transaction revision overflowed."
            )
        }
        return DocumentTransactionRevision(value + 1)
    }

    public static func < (
        lhs: DocumentTransactionRevision,
        rhs: DocumentTransactionRevision
    ) -> Bool {
        lhs.value < rhs.value
    }
}
