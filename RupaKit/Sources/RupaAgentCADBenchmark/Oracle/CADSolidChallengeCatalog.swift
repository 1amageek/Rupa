import Foundation

enum CADSolidChallengeCatalog {
    static let definitions: [CADCanonicalChallengeDefinition] = [
        box("BOX-001", 10.0, 10.0, 10.0, .millimeter, 0.0, 0.0, 0.0),
        box("BOX-002", 25.0, 25.0, 25.0, .millimeter, 20.0, -20.0, 0.0),
        box("BOX-003", 50.0, 30.0, 20.0, .millimeter, -25.0, 15.0, 5.0),
        box("BOX-004", 100.0, 50.0, 75.0, .millimeter, 0.0, 0.0, -25.0),
        box("BOX-005", 250.0, 100.0, 125.0, .millimeter, -125.0, -50.0, 0.0),
        box("BOX-006", 0.1, 0.05, 0.025, .meter, 0.0, 0.0, 0.0),
        box("BOX-007", 1.0, 2.0, 3.0, .inch, -1.0, -1.0, 0.0),
        box("BOX-008", 300.0, 300.0, 300.0, .millimeter, 100.0, 100.0, 100.0),
        box("BOX-009", 12.0, 12.0, 12.0, .millimeter, -12.0, 0.0, 0.0),
        box("BOX-010", 400.0, 200.0, 50.0, .millimeter, 0.0, -100.0, 50.0),
        box("BOX-011", 0.5, 0.5, 0.5, .meter, -0.25, -0.25, 0.0),
        box("BOX-012", 75.0, 125.0, 175.0, .millimeter, 25.0, 25.0, -75.0),

        cylinder("CYL-001", 5.0, 20.0, .millimeter, 0.0, 0.0, 0.0, 0.0, 0.0, 1.0),
        cylinder("CYL-002", 10.0, 50.0, .millimeter, 25.0, -25.0, 0.0, 1.0, 0.0, 0.0),
        cylinder("CYL-003", 25.0, 100.0, .millimeter, -50.0, 20.0, 10.0, 0.0, 1.0, 0.0),
        cylinder("CYL-004", 50.0, 250.0, .millimeter, 0.0, 0.0, -100.0, 0.0, 0.0, -1.0),
        cylinder("CYL-005", 2.0, 10.0, .centimeter, 0.0, 0.0, 0.0, 0.707106781187, 0.707106781187, 0.0),
        cylinder("CYL-006", 0.05, 0.2, .meter, -0.1, 0.05, 0.0, 0.0, 0.707106781187, 0.707106781187),
        cylinder("CYL-007", 1.0, 4.0, .inch, 2.0, 3.0, -1.0, -1.0, 0.0, 0.0),
        cylinder("CYL-008", 75.0, 150.0, .millimeter, 100.0, 100.0, 100.0, 0.57735026919, 0.57735026919, 0.57735026919),

        constraint("CON-001", .coincident, lineInput("first", 20.0, 0.0, 0.0, 20.0), lineInput("second", 0.0, 0.0, 0.0, 20.0)),
        constraint("CON-002", .parallel, lineInput("first", 0.0, 0.0, 40.0, 0.0), lineInput("second", 0.0, 10.0, 50.0, 10.0)),
        constraint("CON-003", .perpendicular, lineInput("first", 0.0, 0.0, 30.0, 0.0), lineInput("second", 0.0, 15.0, 0.0, 45.0)),
        constraint("CON-004", .horizontal, lineInput("first", 0.0, 0.0, 25.0, 0.0), nil),
        constraint("CON-005", .vertical, lineInput("first", 0.0, 0.0, 0.0, 25.0), nil),
        constraint("CON-006", .equalLength, lineInput("first", 0.0, 0.0, 50.0, 0.0), lineInput("second", 0.0, 10.0, 50.0, 10.0)),
        constraint("CON-007", .concentric, circleInput("first", 10.0, 0.0, 0.0), circleInput("second", 25.0, 0.0, 0.0)),
        constraint("CON-008", .equalRadius, circleInput("first", 15.0, 0.0, 0.0), circleInput("second", 15.0, 50.0, 0.0)),

        transform("TRN-001", .line(lineInput("source", 0.0, 0.0, 100.0, 0.0)), 25.0, 0.0, 0.0, 50.0, 0.0, 0.0, 0.0, 0.0, 1.0, 30.0),
        transform("TRN-002", .rectangle(rectangleInput("source", 40.0, 20.0, .xy, 0.0, 0.0)), 0.0, 25.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 1.0, 45.0),
        transform("TRN-003", .circle(circleInput("source", 10.0, 0.0, 0.0)), 0.0, 0.0, 50.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 90.0),
        transform("TRN-004", .box(boxInput("source", 20.0, 30.0, 40.0, .millimeter, 0.0, 0.0, 0.0)), 100.0, -50.0, 25.0, 10.0, 15.0, 20.0, 0.0, 0.0, 1.0, 15.0),
        transform("TRN-005", .cylinder(cylinderInput("source", 8.0, 40.0, .millimeter, 0.0, 0.0, 0.0, 0.0, 0.0, 1.0)), -25.0, 50.0, 75.0, 0.0, 0.0, 20.0, 0.0, 1.0, 0.0, 30.0),
        transform("TRN-006", .line(lineInput("source", -30.0, -30.0, 30.0, 30.0)), 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 120.0),
        transform("TRN-007", .rectangle(rectangleInput("source", 100.0, 50.0, .yz, 0.0, 0.0)), 0.0, 0.0, -100.0, 0.0, 0.0, 0.0, 0.0, 0.0, 1.0, 180.0),
        transform("TRN-008", .circle(circleInput("source", 50.0, 25.0, -25.0)), 250.0, 125.0, 0.0, 25.0, -25.0, 0.0, 0.57735026919, 0.57735026919, 0.57735026919, 60.0),

        compound("CMP-001", [member("base", boxInput("base", 100.0, 50.0, 20.0, .millimeter, 0.0, 0.0, 0.0)), member("post", cylinderInput("post", 10.0, 80.0, .millimeter, 50.0, 25.0, 20.0, 0.0, 0.0, 1.0))]),
        compound("CMP-002", [member("left", boxInput("left", 25.0, 25.0, 25.0, .millimeter, -40.0, 0.0, 0.0)), member("right", boxInput("right", 25.0, 25.0, 25.0, .millimeter, 15.0, 0.0, 0.0))]),
        compound("CMP-003", [member("shaft", cylinderInput("shaft", 5.0, 100.0, .millimeter, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0)), member("collar", cylinderInput("collar", 12.0, 10.0, .millimeter, 45.0, 0.0, 0.0, 1.0, 0.0, 0.0))]),
        compound("CMP-004", [member("plate", boxInput("plate", 200.0, 100.0, 10.0, .millimeter, 0.0, 0.0, 0.0)), member("pin-a", cylinderInput("pin-a", 8.0, 50.0, .millimeter, 25.0, 25.0, 10.0, 0.0, 0.0, 1.0)), member("pin-b", cylinderInput("pin-b", 8.0, 50.0, .millimeter, 175.0, 25.0, 10.0, 0.0, 0.0, 1.0))]),
        compound("CMP-005", [member("frame", boxInput("frame", 300.0, 20.0, 20.0, .millimeter, 0.0, 0.0, 0.0)), member("upright-a", boxInput("upright-a", 20.0, 20.0, 100.0, .millimeter, 0.0, 0.0, 20.0)), member("upright-b", boxInput("upright-b", 20.0, 20.0, 100.0, .millimeter, 280.0, 0.0, 20.0))]),
        compound("CMP-006", [member("hub", cylinderInput("hub", 20.0, 50.0, .millimeter, 0.0, 0.0, 0.0, 0.0, 0.0, 1.0)), member("arm-a", boxInput("arm-a", 100.0, 10.0, 10.0, .millimeter, 20.0, -5.0, 20.0)), member("arm-b", boxInput("arm-b", 100.0, 10.0, 10.0, .millimeter, -120.0, -5.0, 20.0))]),
        compound("CMP-007", [member("block", boxInput("block", 50.0, 50.0, 50.0, .millimeter, 0.0, 0.0, 0.0)), member("bore", cylinderInput("bore", 10.0, 50.0, .millimeter, 25.0, 25.0, 0.0, 0.0, 0.0, 1.0))]),

        sphere("SPH-001", 5.0, .millimeter, 0.0, 0.0, 0.0),
        sphere("SPH-002", 25.0, .millimeter, 50.0, -25.0, 10.0),
        sphere("SPH-003", 0.1, .meter, 0.0, 0.0, 0.1),
        sphere("SPH-004", 2.0, .inch, -2.0, 3.0, 1.0),
        sphere("SPH-005", 100.0, .millimeter, -100.0, 100.0, -50.0),
    ]

    private static func base(
        _ id: String,
        _ category: CADBenchmarkCategory,
        _ input: CADChallengeInput,
        _ roles: [CADOutputRole]
    ) -> CADCanonicalChallengeDefinition {
        CADCanonicalChallengeDefinition(
            id: CADBenchmarkCaseID(rawValue: id),
            category: category,
            input: input,
            outputRoles: roles,
            requiredCapability: CADCapabilityRequirement(id: category.capabilityID, version: "1")
        )
    }

    private static func box(
        _ id: String,
        _ width: Double,
        _ depth: Double,
        _ height: Double,
        _ unit: CADLengthUnit,
        _ x: Double,
        _ y: Double,
        _ z: Double
    ) -> CADCanonicalChallengeDefinition {
        let input = CADBoxChallengeInput(
            origin: CADPoint3D(x: x, y: y, z: z, unit: unit),
            width: CADLength(value: width, unit: unit),
            depth: CADLength(value: depth, unit: unit),
            height: CADLength(value: height, unit: unit)
        )
        return base(id, .box, .box(input), [CADOutputRole(name: "solid", description: "The requested closed box solid.")])
    }

    private static func cylinder(
        _ id: String,
        _ radius: Double,
        _ depth: Double,
        _ unit: CADLengthUnit,
        _ x: Double,
        _ y: Double,
        _ z: Double,
        _ axisX: Double,
        _ axisY: Double,
        _ axisZ: Double
    ) -> CADCanonicalChallengeDefinition {
        let input = CADCylinderChallengeInput(
            baseCenter: CADPoint3D(x: x, y: y, z: z, unit: unit),
            axis: CADDirection3D(x: axisX, y: axisY, z: axisZ),
            radius: CADLength(value: radius, unit: unit),
            depth: CADLength(value: depth, unit: unit)
        )
        return base(id, .cylinder, .cylinder(input), [CADOutputRole(name: "solid", description: "The requested analytic cylinder solid.")])
    }

    private static func lineInput(_ name: String, _ x1: Double, _ y1: Double, _ x2: Double, _ y2: Double) -> CADLineChallengeInput {
        CADLineChallengeInput(
            start: CADPoint3D(x: x1, y: y1, z: 0.0),
            end: CADPoint3D(x: x2, y: y2, z: 0.0),
            length: CADLength(value: hypot(x2 - x1, y2 - y1)),
            plane: .xy
        )
    }

    private static func circleInput(_ name: String, _ radius: Double, _ x: Double, _ y: Double) -> CADCircleChallengeInput {
        CADCircleChallengeInput(
            center: CADPoint3D(x: x, y: y, z: 0.0),
            radius: CADLength(value: radius),
            plane: .xy
        )
    }

    private static func rectangleInput(_ name: String, _ width: Double, _ height: Double, _ plane: CADSketchPlane, _ centerX: Double, _ centerY: Double) -> CADRectangleChallengeInput {
        CADRectangleChallengeInput(
            center: CADPoint3D(x: centerX, y: centerY, z: 0.0),
            width: CADLength(value: width),
            height: CADLength(value: height),
            plane: plane
        )
    }

    private static func boxInput(_ name: String, _ width: Double, _ depth: Double, _ height: Double, _ unit: CADLengthUnit, _ x: Double, _ y: Double, _ z: Double) -> CADBoxChallengeInput {
        CADBoxChallengeInput(
            origin: CADPoint3D(x: x, y: y, z: z, unit: unit),
            width: CADLength(value: width, unit: unit),
            depth: CADLength(value: depth, unit: unit),
            height: CADLength(value: height, unit: unit)
        )
    }

    private static func cylinderInput(_ name: String, _ radius: Double, _ depth: Double, _ unit: CADLengthUnit, _ x: Double, _ y: Double, _ z: Double, _ axisX: Double, _ axisY: Double, _ axisZ: Double) -> CADCylinderChallengeInput {
        CADCylinderChallengeInput(
            baseCenter: CADPoint3D(x: x, y: y, z: z, unit: unit),
            axis: CADDirection3D(x: axisX, y: axisY, z: axisZ),
            radius: CADLength(value: radius, unit: unit),
            depth: CADLength(value: depth, unit: unit)
        )
    }

    private static func constraint(
        _ id: String,
        _ relation: CADConstraintKind,
        _ first: CADLineChallengeInput,
        _ second: CADLineChallengeInput?
    ) -> CADCanonicalChallengeDefinition {
        base(
            id,
            .constraint,
            .constraint(CADConstraintChallengeInput(
                relation: relation,
                first: .line(first),
                second: second.map(CADConstraintGeometryInput.line)
            )),
            [CADOutputRole(name: "relation", description: "The requested source sketch relation.")]
        )
    }

    private static func constraint(
        _ id: String,
        _ relation: CADConstraintKind,
        _ first: CADCircleChallengeInput,
        _ second: CADCircleChallengeInput?
    ) -> CADCanonicalChallengeDefinition {
        base(
            id,
            .constraint,
            .constraint(CADConstraintChallengeInput(
                relation: relation,
                first: .circle(first),
                second: second.map(CADConstraintGeometryInput.circle)
            )),
            [CADOutputRole(name: "relation", description: "The requested source sketch relation.")]
        )
    }

    private static func transform(
        _ id: String,
        _ source: CADTransformSource,
        _ tx: Double,
        _ ty: Double,
        _ tz: Double,
        _ axisPointX: Double,
        _ axisPointY: Double,
        _ axisPointZ: Double,
        _ axisX: Double,
        _ axisY: Double,
        _ axisZ: Double,
        _ degrees: Double
    ) -> CADCanonicalChallengeDefinition {
        let input = CADTransformChallengeInput(
            source: source,
            translation: CADPoint3D(x: tx, y: ty, z: tz),
            axisPoint: CADPoint3D(x: axisPointX, y: axisPointY, z: axisPointZ),
            rotationAxis: CADDirection3D(x: axisX, y: axisY, z: axisZ),
            rotation: CADAngle(value: degrees)
        )
        return base(id, .transform, .transform(input), [CADOutputRole(name: "transformed-source", description: "The source geometry after the requested placement.")])
    }

    private static func member(_ role: String, _ box: CADBoxChallengeInput) -> CADCompoundMemberInput {
        CADCompoundMemberInput(role: role, box: box)
    }

    private static func member(_ role: String, _ cylinder: CADCylinderChallengeInput) -> CADCompoundMemberInput {
        CADCompoundMemberInput(role: role, cylinder: cylinder)
    }

    private static func compound(_ id: String, _ members: [CADCompoundMemberInput]) -> CADCanonicalChallengeDefinition {
        base(
            id,
            .compound,
            .compound(CADCompoundChallengeInput(members: members)),
            members.map { CADOutputRole(name: $0.role, description: "The requested compound member \($0.role).") }
        )
    }

    private static func sphere(
        _ id: String,
        _ radius: Double,
        _ unit: CADLengthUnit,
        _ x: Double,
        _ y: Double,
        _ z: Double
    ) -> CADCanonicalChallengeDefinition {
        let input = CADSphereChallengeInput(
            center: CADPoint3D(x: x, y: y, z: z, unit: unit),
            radius: CADLength(value: radius, unit: unit)
        )
        return base(id, .sphere, .sphere(input), [CADOutputRole(name: "sphere", description: "The requested analytic sphere.")])
    }
}
