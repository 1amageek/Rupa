import Foundation

/// One candidate-owned compound intent lowered atomically by the compound facade.
public struct CADCompoundAction: Codable, Equatable, Hashable, Sendable {
    public let members: [CADCompoundMemberAction]

    public init(members: [CADCompoundMemberAction]) {
        self.members = members
    }
}
