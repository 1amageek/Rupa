import Foundation

/// A request-local identifier for a prepared program input or output slot.
public struct PreparedAutomationSlotID: Sendable, Equatable, Hashable, CustomStringConvertible {
    public let rawValue: String

    public init(_ rawValue: String) {
        self.rawValue = rawValue
    }

    public var description: String {
        rawValue
    }
}
