import Foundation

enum CADSketchChallengeCatalog {
    static let definitions: [CADCanonicalChallengeDefinition] = [
        line("LIN-001", 25.0, .millimeter, .xy, 0.0, 0.0, 25.0, 0.0),
        line("LIN-002", 50.0, .millimeter, .xy, 10.0, -10.0, 10.0, 40.0),
        line("LIN-003", 60.0, .millimeter, .xy, -30.0, 15.0, 30.0, 15.0),
        line3("LIN-004", 100.0, .millimeter, .xz, 0.0, 0.0, 0.0, 0.0, 0.0, 100.0),
        line3("LIN-005", 150.0, .millimeter, .yz, 0.0, 20.0, 0.0, 0.0, 170.0, 0.0),
        line("LIN-006", 50.0, .millimeter, .xy, 0.0, 0.0, 30.0, 40.0),
        line("LIN-007", 80.0, .millimeter, .xy, 40.0, 20.0, -40.0, 20.0),
        line("LIN-008", 125.0, .centimeter, .xy, -20.0, -20.0, 105.0, -20.0),
        line3("LIN-009", 0.25, .meter, .xz, 0.0, 0.0, 0.0, 0.25, 0.0, 0.0),
        line("LIN-010", 10.0, .inch, .yz, -5.0, 0.0, -5.0, 10.0),
        line3("LIN-011", 2.0, .meter, .xz, 0.0, 0.0, 0.0, 0.0, 0.0, -2.0),
        line("LIN-012", 375.0, .millimeter, .xy, 125.0, -75.0, 500.0, -75.0),

        rectangle("REC-001", 40.0, 20.0, .millimeter, .xy, 0.0, 0.0, 0.0),
        rectangle("REC-002", 80.0, 30.0, .millimeter, .xy, 15.0, -20.0, 0.0),
        rectangle("REC-003", 120.0, 60.0, .millimeter, .xz, 0.0, 0.0, 25.0),
        rectangle("REC-004", 250.0, 100.0, .millimeter, .yz, -50.0, 0.0, 0.0),
        rectangle("REC-005", 10.0, 5.0, .centimeter, .xy, 0.0, 0.0, 0.0),
        rectangle("REC-006", 0.4, 0.2, .meter, .xz, 0.0, 0.0, 0.0),
        rectangle("REC-007", 12.0, 90.0, .millimeter, .yz, 20.0, -40.0, 0.0),
        rectangle("REC-008", 500.0, 125.0, .millimeter, .xy, -250.0, 125.0, 0.0),
        rectangle("REC-009", 1.0, 0.5, .inch, .xz, 0.0, 0.0, 0.0),
        rectangle("REC-010", 2.0, 1.0, .meter, .xy, 0.0, 0.0, 0.0),
        rectangle("REC-011", 35.0, 35.0, .millimeter, .yz, 0.0, 15.0, -15.0),
        rectangle("REC-012", 750.0, 80.0, .millimeter, .xy, -100.0, -40.0, 0.0),

        circle("CIR-001", 5.0, .millimeter, .xy, 0.0, 0.0, 0.0),
        circle("CIR-002", 12.5, .millimeter, .xy, 25.0, -10.0, 0.0),
        circle("CIR-003", 25.0, .millimeter, .xz, 0.0, 0.0, 50.0),
        circle("CIR-004", 50.0, .millimeter, .yz, -75.0, 0.0, 0.0),
        circle("CIR-005", 100.0, .millimeter, .xy, 100.0, 100.0, 0.0),
        circle("CIR-006", 2.0, .centimeter, .xz, 0.0, 0.0, 20.0),
        circle("CIR-007", 0.1, .meter, .yz, 0.0, -0.1, 0.0),
        circle("CIR-008", 1.0, .inch, .xy, -2.0, 3.0, 0.0),
        circle("CIR-009", 250.0, .millimeter, .xz, 0.0, 0.0, -125.0),
        circle("CIR-010", 0.5, .meter, .xy, 0.5, -0.5, 0.0),
        circle("CIR-011", 7.25, .millimeter, .yz, 20.0, 0.0, 30.0),
        circle("CIR-012", 42.0, .millimeter, .xy, -80.0, 45.0, 0.0),

        angle("ANG-001", 15.0, 30.0, 25.0, 35.0, 0.0, 0.0, 1.0, 0.0, 0.866025403784, 0.5),
        angle("ANG-002", 30.0, 45.0, 50.0, 50.0, 10.0, -10.0, 1.0, 0.0, 0.707106781187, 0.707106781187),
        angle("ANG-003", 45.0, 60.0, 75.0, 125.0, -25.0, 15.0, 1.0, 0.0, 0.5, 0.866025403784),
        angle("ANG-004", 60.0, 75.0, 100.0, 150.0, 30.0, 25.0, 1.0, 0.0, 0.258819045103, 0.965925826289),
        angle("ANG-005", 75.0, 90.0, 125.0, 200.0, 0.0, 0.0, 1.0, 0.0, 0.0, 1.0),
        angle("ANG-006", 90.0, 105.0, 150.0, 250.0, -50.0, 40.0, 1.0, 0.0, -0.258819045103, 0.965925826289),
        angle("ANG-007", 105.0, 120.0, 200.0, 300.0, 20.0, -35.0, 1.0, 0.0, -0.5, 0.866025403784),
        angle("ANG-008", 120.0, 135.0, 250.0, 350.0, 0.0, 0.0, 1.0, 0.0, -0.707106781187, 0.707106781187),
        angle("ANG-009", 135.0, 150.0, 300.0, 400.0, 75.0, 50.0, 1.0, 0.0, -0.866025403784, 0.5),
        angle("ANG-010", 150.0, 165.0, 350.0, 450.0, -75.0, -50.0, 1.0, 0.0, -0.965925826289, 0.258819045103),
        anglePlane("ANG-011", 30.0, 45.0, 60.0, 80.0, .xz, 0.0, 0.0, 1.0, 0.0, 0.707106781187, 0.707106781187),
        anglePlane("ANG-012", 40.0, 60.0, 100.0, 120.0, .yz, 10.0, -20.0, 1.0, 0.0, 0.5, 0.866025403784),
        anglePlane("ANG-013", 50.0, 90.0, 150.0, 180.0, .xz, -15.0, 25.0, 1.0, 0.0, 0.0, 1.0),
        anglePlane("ANG-014", 75.0, 120.0, 225.0, 275.0, .yz, -25.0, 30.0, 1.0, 0.0, -0.5, 0.866025403784),
        anglePlane("ANG-015", 100.0, 135.0, 300.0, 325.0, .xz, 40.0, -40.0, 1.0, 0.0, -0.707106781187, 0.707106781187),
        anglePlane("ANG-016", 125.0, 150.0, 375.0, 425.0, .yz, 60.0, 60.0, 1.0, 0.0, -0.866025403784, 0.5),
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

    private static func line(
        _ id: String,
        _ length: Double,
        _ unit: CADLengthUnit,
        _ plane: CADSketchPlane,
        _ startX: Double,
        _ startY: Double,
        _ endX: Double,
        _ endY: Double
    ) -> CADCanonicalChallengeDefinition {
        let input = CADLineChallengeInput(
            start: CADPoint3D(x: startX, y: startY, z: 0.0, unit: unit),
            end: CADPoint3D(x: endX, y: endY, z: 0.0, unit: unit),
            length: CADLength(value: length, unit: unit),
            plane: plane
        )
        return base(id, .line, .line(input), [CADOutputRole(name: "segment", description: "The requested finite line segment.")])
    }

    private static func line3(
        _ id: String,
        _ length: Double,
        _ unit: CADLengthUnit,
        _ plane: CADSketchPlane,
        _ startX: Double,
        _ startY: Double,
        _ startZ: Double,
        _ endX: Double,
        _ endY: Double,
        _ endZ: Double
    ) -> CADCanonicalChallengeDefinition {
        let input = CADLineChallengeInput(
            start: CADPoint3D(x: startX, y: startY, z: startZ, unit: unit),
            end: CADPoint3D(x: endX, y: endY, z: endZ, unit: unit),
            length: CADLength(value: length, unit: unit),
            plane: plane
        )
        return base(id, .line, .line(input), [CADOutputRole(name: "segment", description: "The requested finite line segment.")])
    }

    private static func rectangle(
        _ id: String,
        _ width: Double,
        _ height: Double,
        _ unit: CADLengthUnit,
        _ plane: CADSketchPlane,
        _ x: Double,
        _ y: Double,
        _ z: Double
    ) -> CADCanonicalChallengeDefinition {
        let input = CADRectangleChallengeInput(
            origin: CADPoint3D(x: x, y: y, z: z, unit: unit),
            width: CADLength(value: width, unit: unit),
            height: CADLength(value: height, unit: unit),
            plane: plane
        )
        return base(id, .rectangle, .rectangle(input), [CADOutputRole(name: "rectangle", description: "The requested closed rectangle.")])
    }

    private static func circle(
        _ id: String,
        _ radius: Double,
        _ unit: CADLengthUnit,
        _ plane: CADSketchPlane,
        _ x: Double,
        _ y: Double,
        _ z: Double
    ) -> CADCanonicalChallengeDefinition {
        let input = CADCircleChallengeInput(
            center: CADPoint3D(x: x, y: y, z: z, unit: unit),
            radius: CADLength(value: radius, unit: unit),
            plane: plane
        )
        return base(id, .circle, .circle(input), [CADOutputRole(name: "circle", description: "The requested analytic circle.")])
    }

    private static func angle(
        _ id: String,
        _ firstLength: Double,
        _ degrees: Double,
        _ secondLength: Double,
        _ z: Double,
        _ x: Double,
        _ y: Double,
        _ firstX: Double,
        _ firstY: Double,
        _ secondX: Double,
        _ secondY: Double
    ) -> CADCanonicalChallengeDefinition {
        anglePlane(id, firstLength, degrees, secondLength, z, .xy, x, y, firstX, firstY, secondX, secondY)
    }

    private static func anglePlane(
        _ id: String,
        _ firstLength: Double,
        _ degrees: Double,
        _ secondLength: Double,
        _ z: Double,
        _ plane: CADSketchPlane,
        _ x: Double,
        _ y: Double,
        _ firstX: Double,
        _ firstY: Double,
        _ secondX: Double,
        _ secondY: Double
    ) -> CADCanonicalChallengeDefinition {
        let input = CADAngleChallengeInput(
            intersection: CADPoint3D(x: x, y: y, z: z, unit: .millimeter),
            firstDirection: direction(firstX, firstY, plane: plane),
            secondDirection: direction(secondX, secondY, plane: plane),
            firstLength: CADLength(value: firstLength, unit: .millimeter),
            secondLength: CADLength(value: secondLength, unit: .millimeter),
            includedAngle: CADAngle(value: degrees, unit: .degree),
            plane: plane
        )
        return base(id, .angle, .angle(input), [
            CADOutputRole(name: "first-line", description: "The first finite line at the intersection."),
            CADOutputRole(name: "second-line", description: "The second finite line at the intersection.")
        ])
    }

    private static func direction(_ localX: Double, _ localY: Double, plane: CADSketchPlane) -> CADDirection3D {
        switch plane {
        case .xy:
            CADDirection3D(x: localX, y: localY, z: 0.0)
        case .xz:
            CADDirection3D(x: localX, y: 0.0, z: localY)
        case .yz:
            CADDirection3D(x: 0.0, y: localX, z: localY)
        }
    }
}
