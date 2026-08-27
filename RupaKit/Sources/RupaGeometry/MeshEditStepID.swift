import Foundation

/// A stable caller-provided identifier for one ordered plan step.
public struct MeshEditStepID: Codable, Equatable, Hashable, Comparable, Sendable {
    public let rawValue: String

    public init(_ rawValue: String) {
        self.rawValue = rawValue
    }

    public static func < (lhs: MeshEditStepID, rhs: MeshEditStepID) -> Bool {
        lhs.rawValue < rhs.rawValue
    }

    var isStructurallyValid: Bool {
        !rawValue.isEmpty
            && rawValue.utf8.count <= 256
            && rawValue.utf8.allSatisfy { $0 >= 0x21 && $0 <= 0x7E }
    }
}
