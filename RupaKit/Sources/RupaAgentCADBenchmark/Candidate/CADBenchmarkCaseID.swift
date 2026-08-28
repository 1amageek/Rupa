import Foundation

public struct CADBenchmarkCaseID: Codable, Comparable, Equatable, Hashable, Sendable,
    CustomStringConvertible, ExpressibleByStringLiteral {
    public let rawValue: String

    public init(rawValue: String) {
        self.rawValue = rawValue
    }

    public init(stringLiteral value: String) {
        self.rawValue = value
    }

    public init(validating rawValue: String) throws {
        self.init(rawValue: rawValue)
        try validate()
    }

    public var description: String {
        rawValue
    }

    public var category: CADBenchmarkCategory? {
        guard let separator = rawValue.firstIndex(of: "-") else {
            return nil
        }
        return CADBenchmarkCategory(rawValue: String(rawValue[..<separator]))
    }

    public func validate() throws {
        let parts = rawValue.split(separator: "-", omittingEmptySubsequences: false)
        guard parts.count == 2,
              let category = CADBenchmarkCategory(rawValue: String(parts[0])),
              parts[1].count == 3,
              parts[1].allSatisfy({ $0.isNumber }),
              let ordinal = Int(parts[1]),
              ordinal >= 1,
              ordinal <= category.expectedCount else {
            throw CADBenchmarkError.invalidCaseID(rawValue)
        }
    }

    public static func < (lhs: Self, rhs: Self) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}
