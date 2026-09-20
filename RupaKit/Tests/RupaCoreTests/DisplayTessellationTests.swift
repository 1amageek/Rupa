import Foundation
import SwiftCAD
import Testing
@testable import RupaCore

@Suite("Display tessellation")
struct DisplayTessellationTests {
    private static let profileRadius = 0.05
    private static let cornerRadius = 0.01

    @Test(.timeLimit(.minutes(1)))
    func everyCountTheSchemaOffersIsTheNumberOfProfileSamplesTheMeshCarries() throws {
        let range = try #require(Self.sideCountRange())
        let step = try #require(range.step)
        let lowest = Int(range.lowerBound)
        let offered = [lowest, lowest + Int(step), lowest + 3 * Int(step), 64, Int(range.upperBound)]
        for declared in offered {
            var document = try Self.cylinderDocument()
            let node = try Self.bodyNode(of: document)
            try document.setSceneNodeObjectProperty(
                id: node.id,
                propertyID: "sides.x",
                value: .integer(declared)
            )
            let evaluated = try DocumentEvaluator
                .modelingDefault(for: document)
                .evaluate(document.cadDocument)
            #expect(Self.profileSampleCount(of: evaluated) == declared)
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func aCountBetweenTheOnesTheSchemaOffersIsRefusedInsteadOfRedrawn() throws {
        let range = try #require(Self.sideCountRange())
        let step = try #require(range.step)
        let between = Int(range.lowerBound) + Int(step) / 2
        var document = try Self.cylinderDocument()
        let node = try Self.bodyNode(of: document)
        #expect(throws: (any Error).self) {
            try document.setSceneNodeObjectProperty(
                id: node.id,
                propertyID: "sides.x",
                value: .integer(between)
            )
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func everyCornerCountTheSchemaOffersIsTheNumberOfSegmentsTheRoundedCornerCarries() throws {
        let declared = try #require(
            ObjectTypeRegistry.builtIn
                .definition(for: .cube)?
                .property(for: PropertyID("corner.sides"))
        )
        let range = try #require(declared.numericRange)
        let step = try #require(range.step)
        let lowest = Int(range.lowerBound)
        for count in [lowest, lowest + Int(step), lowest + 3 * Int(step)] {
            var document = try Self.roundedBoxDocument(cornerRadius: Self.cornerRadius)
            let node = try Self.bodyNode(of: document)
            try document.setSceneNodeObjectProperty(
                id: node.id,
                propertyID: "corner.sides",
                value: .integer(count)
            )
            let evaluated = try DocumentEvaluator
                .modelingDefault(for: document)
                .evaluate(document.cadDocument)
            #expect(Self.roundedCornerSegmentCount(of: evaluated) == count)
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func aCylinderIsDrawnAtTheSideCountItDeclaresInsteadOfTheDocumentTolerance() throws {
        let document = try Self.cylinderDocument()
        let declared = try #require(
            ObjectTypeRegistry.builtIn
                .definition(for: .cylinder)?
                .property(for: PropertyID("sides.x"))
        )
        guard case .integer(let sideCount) = declared.defaultValue else {
            Issue.record("The declared side count must be a whole number.")
            return
        }

        let routed = try DocumentEvaluator
            .modelingDefault(for: document)
            .evaluate(document.cadDocument)
        let unrouted = try DocumentEvaluator(
            tolerance: document.modelingSettings.tolerance,
            tessellationOptions: document.modelingSettings.tessellationOptions,
            artifactPolicy: .materialized
        ).evaluate(document.cadDocument)

        #expect(Self.profileSampleCount(of: routed) == sideCount)
        #expect(Self.profileSampleCount(of: unrouted) > sideCount * 10)
    }

    @Test(.timeLimit(.minutes(1)))
    func aDeclaredCountResolvesTheArcItDividesAndNothingElse() throws {
        var document = try Self.cylinderDocument()
        let node = try Self.bodyNode(of: document)
        let featureID = try #require(node.object?.sourceFeatureID)

        let options = try document.displayTessellationOptions()
        let override = try #require(options.featureOverrides[featureID])
        // The profile is one full turn, so the side count divides `2 * .pi`.
        #expect(Self.approximatelyEqual(override.angularTolerance, 2.0 * .pi / 63.5))
        #expect(Self.approximatelyEqual(
            override.linearTolerance,
            Self.profileRadius * (1.0 - cos(.pi / 64.0))
        ))
        #expect(options.featureOverrides.count == 1)

        // The corner count divides an arc the body does not hold, so it claims nothing.
        try document.setSceneNodeObjectProperty(
            id: node.id,
            propertyID: "corner.sides",
            value: .integer(3)
        )
        let unchanged = try document.displayTessellationOptions()
        #expect(unchanged.featureOverrides[featureID] == override)
    }

    @Test(.timeLimit(.minutes(1)))
    func aRoundedBoxResolvesTheCornerCountAgainstTheFilletItRounds() throws {
        var document = try Self.boxDocument()
        let node = try Self.bodyNode(of: document)

        // A box with square corners holds no arc, so no count reaches the evaluator.
        #expect(try document.displayTessellationOptions().featureOverrides.isEmpty)

        try document.setSceneNodeObjectProperty(
            id: node.id,
            propertyID: "corner.radius",
            value: .length(Self.cornerRadius)
        )
        let featureID = try #require(
            document.productMetadata.sceneNodes[node.id]?.object?.sourceFeatureID
        )
        let override = try #require(
            try document.displayTessellationOptions().featureOverrides[featureID]
        )
        // One rounded corner is a quarter turn, so the corner count divides `.pi / 2`.
        #expect(Self.approximatelyEqual(override.angularTolerance, (.pi / 2.0) / 7.5))
        #expect(Self.approximatelyEqual(
            override.linearTolerance,
            Self.cornerRadius * (1.0 - cos(.pi / 32.0))
        ))
    }

    // MARK: - Helpers

    /// The counts the schema offers for the side subdivision of a cylinder.
    private static func sideCountRange() -> ObjectPropertyDefinition.NumericRange? {
        ObjectTypeRegistry.builtIn
            .definition(for: .cylinder)?
            .property(for: PropertyID("sides.x"))?
            .numericRange
    }

    private static func cylinderDocument() throws -> DesignDocument {
        var document = DesignDocument.empty()
        _ = try document.createExtrudedCircle(
            name: "Cylinder",
            plane: .xy,
            center: SketchPoint(x: .length(0.0, .meter), y: .length(0.0, .meter)),
            radius: .length(profileRadius, .meter),
            depth: .length(0.1, .meter),
            direction: .normal
        )
        return document
    }

    private static func boxDocument() throws -> DesignDocument {
        var document = DesignDocument.empty()
        _ = try document.createExtrudedRectangle(
            name: "Box",
            plane: .xy,
            width: .length(0.1, .meter),
            height: .length(0.08, .meter),
            depth: .length(0.06, .meter),
            direction: .normal
        )
        return document
    }

    private static func roundedBoxDocument(cornerRadius: Double) throws -> DesignDocument {
        var document = try boxDocument()
        let node = try bodyNode(of: document)
        try document.setSceneNodeObjectProperty(
            id: node.id,
            propertyID: "corner.radius",
            value: .length(cornerRadius)
        )
        return document
    }

    private static func bodyNode(of document: DesignDocument) throws -> SceneNode {
        try #require(document.productMetadata.sceneNodes.values.first {
            $0.object?.category == .body
        })
    }

    /// The number of distinct turns around the extrusion axis the mesh samples the profile at.
    ///
    /// The profile is a circle on the `xy` plane, so every vertex off the axis lies on one of the
    /// angles the sampler chose, and the sweep and the caps share those angles.
    private static func profileSampleCount(of evaluated: EvaluatedDocument) -> Int {
        var angles: [Double] = []
        for mesh in evaluated.meshes.values {
            for position in mesh.positions {
                let distance = (position.x * position.x + position.y * position.y).squareRoot()
                guard distance > 1.0e-9 else { continue }
                let angle = atan2(position.y, position.x)
                angles.append(angle < 0 ? angle + 2.0 * .pi : angle)
            }
        }
        guard !angles.isEmpty else { return 0 }
        angles.sort()
        let separation = 1.0e-7
        var count = 0
        var previous = -Double.infinity
        for angle in angles where angle - previous > separation {
            count += 1
            previous = angle
        }
        // The first and last samples are the same turn when the sweep starts on the seam.
        if count > 1, angles[0] + 2.0 * .pi - previous <= separation {
            count -= 1
        }
        return count
    }

    /// The number of segments one rounded corner of the box carries.
    ///
    /// The corner nearest the largest `x` and `y` is a quarter turn about the axis through the
    /// fillet's centre, so every vertex on it sits at the fillet radius from that centre. An open
    /// arc carries one more sample than it has segments.
    private static func roundedCornerSegmentCount(of evaluated: EvaluatedDocument) -> Int {
        var maximumX = -Double.infinity
        var maximumY = -Double.infinity
        for mesh in evaluated.meshes.values {
            for position in mesh.positions {
                maximumX = max(maximumX, position.x)
                maximumY = max(maximumY, position.y)
            }
        }
        guard maximumX.isFinite, maximumY.isFinite else { return 0 }
        let centerX = maximumX - cornerRadius
        let centerY = maximumY - cornerRadius
        var angles: [Double] = []
        for mesh in evaluated.meshes.values {
            for position in mesh.positions {
                let dx = position.x - centerX
                let dy = position.y - centerY
                guard dx > -1.0e-9, dy > -1.0e-9 else { continue }
                let distance = (dx * dx + dy * dy).squareRoot()
                guard abs(distance - cornerRadius) < 1.0e-6 else { continue }
                angles.append(atan2(dy, dx))
            }
        }
        guard !angles.isEmpty else { return 0 }
        angles.sort()
        let separation = 1.0e-7
        var count = 0
        var previous = -Double.infinity
        for angle in angles where angle - previous > separation {
            count += 1
            previous = angle
        }
        return count - 1
    }

    private static func approximatelyEqual(
        _ lhs: Double,
        _ rhs: Double,
        tolerance: Double = 1.0e-12
    ) -> Bool {
        abs(lhs - rhs) <= tolerance * max(1.0, abs(rhs))
    }
}
