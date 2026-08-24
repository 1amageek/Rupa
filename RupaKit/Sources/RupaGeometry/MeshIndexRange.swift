import Foundation

public struct MeshIndexRange: Codable, Equatable, Hashable, Sendable {
    public var start: Int
    public var count: Int

    public init(start: Int, count: Int) {
        self.start = start
        self.count = count
    }

    public var end: Int {
        start + count
    }

    public func validate(upperBound: Int) throws {
        let computedEnd = start.addingReportingOverflow(count)
        guard start >= 0,
              count >= 0,
              upperBound >= 0,
              !computedEnd.overflow,
              start <= upperBound,
              computedEnd.partialValue <= upperBound else {
            throw MeshSourceError(
                code: .invalidFaceLoop,
                message: "Mesh index ranges must remain within their buffer bounds."
            )
        }
    }
}
