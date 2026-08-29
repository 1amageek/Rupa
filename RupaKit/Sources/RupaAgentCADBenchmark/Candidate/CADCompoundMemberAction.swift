import Foundation

/// One ordered candidate-owned primitive member in a compound intent.
public struct CADCompoundMemberAction: Codable, Equatable, Hashable, Sendable {
    public let role: String
    public let solid: CADSolidAction

    public init(role: String, solid: CADSolidAction) {
        self.role = role
        self.solid = solid
    }

    public init(
        role: String,
        name: String,
        origin: CADPoint3D,
        width: CADLength,
        depth: CADLength,
        height: CADLength
    ) {
        self.init(
            role: role,
            solid: .box(
                name: name,
                origin: origin,
                width: width,
                depth: depth,
                height: height
            )
        )
    }

    public init(
        role: String,
        name: String,
        baseCenter: CADPoint3D,
        axis: CADDirection3D,
        radius: CADLength,
        depth: CADLength
    ) {
        self.init(
            role: role,
            solid: .cylinder(
                name: name,
                baseCenter: baseCenter,
                axis: axis,
                radius: radius,
                depth: depth
            )
        )
    }

    var primitive: CADPrimitiveKind {
        switch solid {
        case .box:
            .box
        case .cylinder:
            .cylinder
        }
    }
}
