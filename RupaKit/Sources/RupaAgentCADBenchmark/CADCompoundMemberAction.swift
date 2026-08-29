import RupaAgentProtocol

/// One candidate-owned compound member intent.
///
/// The role is intentionally kept beside the public solid payload so that a
/// compound plan can preserve semantic output order without exposing any
/// authority or FeatureID information to the candidate.
struct CADCompoundMemberAction: Equatable, Sendable {
    let role: String
    let solid: CADSolidAction

    init(role: String, solid: CADSolidAction) {
        self.role = role
        self.solid = solid
    }

    init(
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

    init(
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

    func asCandidateAction() -> CADCandidateAction {
        .automation(.solid(solid))
    }
}
