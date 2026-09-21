enum CADChallengeInstruction {
    static func make(id: CADBenchmarkCaseID, category _: CADBenchmarkCategory, input: CADChallengeInput) -> String {
        switch input {
        case let .line(input):
            return "Construct \(id) as a finite line segment of length \(length(input.length)) from \(point(input.start)) to \(point(input.end)) on the \(input.plane.rawValue.uppercased())-oriented plane through \(point(input.start))."
        case let .rectangle(input):
            return "Construct \(id) as a rectangle of width \(length(input.width)) and height \(length(input.height)) centered at \(point(input.center)) on the \(input.plane.rawValue) plane."
        case let .circle(input):
            return "Construct \(id) as a circle of radius \(length(input.radius)) centered at \(point(input.center)) on the \(input.plane.rawValue) plane."
        case let .angle(input):
            return "Construct \(id) as two oriented finite line segments. Both segments start at intersection \(point(input.intersection)), which is the source-plane origin. The first has length \(length(input.firstLength)) and direction \(direction(input.firstDirection)). The second has length \(length(input.secondLength)) and direction \(direction(input.secondDirection)). The unsigned included angle is \(angle(input.includedAngle)) on the \(input.plane.rawValue.uppercased())-oriented plane."
        case let .box(input):
            return "Construct \(id) as a closed box with width \(length(input.width)), depth \(length(input.depth)), and height \(length(input.height)) from origin \(point(input.origin))."
        case let .cylinder(input):
            return "Construct \(id) as a closed cylinder with radius \(length(input.radius)) and depth \(length(input.depth)) from base center \(point(input.baseCenter)) along axis \(direction(input.axis))."
        case let .constraint(input):
            let secondGeometry = input.second.map { " and \(constraintGeometry($0))" } ?? ""
            return "Construct \(id) by applying the \(input.relation.rawValue) relation to \(constraintGeometry(input.first))\(secondGeometry)."
        case let .transform(input):
            return "Construct \(id) by first rotating \(transformSource(input.source)) by \(angle(input.rotation)) about the axis through \(point(input.axisPoint)) in direction \(direction(input.rotationAxis)), then translating the rotated result by \(point(input.translation))."
        case let .compound(input):
            let members = input.members.map { member in
                "\(member.role)=\(memberGeometry(member))"
            }.joined(separator: ", ")
            return "Construct \(id) as a compound containing \(members)."
        case let .sphere(input):
            return "Construct \(id) as an analytic sphere of radius \(length(input.radius)) centered at \(point(input.center))."
        }
    }

    private static func length(_ value: CADLength) -> String {
        "\(value.value) \(value.unit.symbol)"
    }

    private static func angle(_ value: CADAngle) -> String {
        "\(value.value) \(value.unit.rawValue)"
    }

    private static func point(_ value: CADPoint3D) -> String {
        "(\(value.x), \(value.y), \(value.z)) \(value.unit.symbol)"
    }

    private static func direction(_ value: CADDirection3D) -> String {
        "(\(value.x), \(value.y), \(value.z))"
    }

    private static func constraintGeometry(_ value: CADConstraintGeometryInput) -> String {
        switch value {
        case let .line(input):
            "line \(point(input.start)) to \(point(input.end))"
        case let .circle(input):
            "circle radius \(length(input.radius)) at \(point(input.center))"
        }
    }

    private static func transformSource(_ value: CADTransformSource) -> String {
        switch value {
        case let .line(input):
            "line \(point(input.start)) to \(point(input.end)) on the \(input.plane.rawValue) plane"
        case let .rectangle(input):
            "rectangle width \(length(input.width)) height \(length(input.height)) centered at \(point(input.center)) on the \(input.plane.rawValue) plane"
        case let .circle(input):
            "circle radius \(length(input.radius)) at \(point(input.center)) on the \(input.plane.rawValue) plane"
        case let .box(input):
            "box \(length(input.width)) x \(length(input.depth)) x \(length(input.height)) at \(point(input.origin))"
        case let .cylinder(input):
            "cylinder radius \(length(input.radius)) depth \(length(input.depth)) at \(point(input.baseCenter)) along axis \(direction(input.axis))"
        }
    }

    private static func memberGeometry(_ value: CADCompoundMemberInput) -> String {
        switch value.primitive {
        case .box:
            guard let input = value.box else { return "box" }
            return "box \(length(input.width)) x \(length(input.depth)) x \(length(input.height)) at \(point(input.origin))"
        case .cylinder:
            guard let input = value.cylinder else { return "cylinder" }
            return "cylinder radius \(length(input.radius)) depth \(length(input.depth)) at \(point(input.baseCenter)) along axis \(direction(input.axis))"
        }
    }
}
