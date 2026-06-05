import Foundation

public struct DocumentGeneration: Codable, Comparable, Hashable, Sendable {
    public var value: UInt64

    public init(_ value: UInt64 = 0) {
        self.value = value
    }

    public func advanced() throws -> DocumentGeneration {
        let (next, overflow) = value.addingReportingOverflow(1)
        guard !overflow else {
            throw RupaError(
                code: .commandFailed,
                message: "Document generation overflowed."
            )
        }
        return DocumentGeneration(next)
    }

    public static func < (lhs: DocumentGeneration, rhs: DocumentGeneration) -> Bool {
        lhs.value < rhs.value
    }
}
