import RupaAgentProtocol
import RupaAutomation
import RupaCore
import SwiftCAD

/// Lowers public compound member intents to the existing primitive commands.
/// The mapping owns no source or project state; atomicity is provided by the
/// enclosing `CADCaseActionPlan.batch` and production controller route.
enum CADCompoundGeometryMapping {
    /// Returns the primitive command capabilities required by an ordered
    /// compound without exposing any private expectation data. The first
    /// occurrence wins, so the result is stable and de-duplicated.
    static func requiredOperationNames(
        for members: [CADCompoundMemberAction]
    ) -> [String] {
        requiredOperationNames(for: members.map(\.primitive))
    }

    /// Returns the capabilities required by the candidate-visible challenge.
    /// Malformed public text has no safely inferable requirement and therefore
    /// produces an empty set; the context factory treats that set as
    /// unavailable instead of falling back to a broader capability.
    static func requiredOperationNames(for challenge: CADChallenge) -> [String] {
        do {
            let projection = try CADCompoundChallengeProjection.decode(challenge)
            return requiredOperationNames(for: projection.members.map(\.primitive))
        } catch {
            return []
        }
    }

    static func requiredOperationNames(
        for primitives: [CADPrimitiveKind]
    ) -> [String] {
        var names: [String] = []
        names.reserveCapacity(primitives.count)
        for primitive in primitives {
            let name: String
            switch primitive {
            case .box:
                name = "createExtrudedRectangle"
            case .cylinder:
                name = "createExtrudedCircle"
            }
            if names.contains(name) == false {
                names.append(name)
            }
        }
        return names
    }

    static func command(
        for submitted: CADCompoundMemberAction,
        expected: CADCompoundChallengeProjection.Member,
        modelingTolerance: ModelingTolerance,
        caseID: CADBenchmarkCaseID
    ) throws -> AutomationCommand {
        guard submitted.role == expected.role else {
            throw CADBenchmarkError.invalidInput(
                caseID: caseID.rawValue,
                reason: "Compound member roles must preserve their declared order."
            )
        }

        switch (expected.primitive, submitted.solid) {
        case let (.box, .box(name, origin, width, depth, height)):
            guard !name.isEmpty else {
                throw CADBenchmarkError.invalidInput(
                    caseID: caseID.rawValue,
                    reason: "A compound box member must have a name."
                )
            }
            try origin.validate(caseID: caseID, field: "compound.\(submitted.role).origin")
            try width.validate(caseID: caseID, field: "compound.\(submitted.role).width")
            try depth.validate(caseID: caseID, field: "compound.\(submitted.role).depth")
            try height.validate(caseID: caseID, field: "compound.\(submitted.role).height")
            let tolerance = try CADBenchmarkTolerancePolicy(modelingTolerance: modelingTolerance)
            guard tolerance.isNonDegenerate(width.meters),
                  tolerance.isNonDegenerate(depth.meters),
                  tolerance.isNonDegenerate(height.meters) else {
                throw CADBenchmarkError.invalidInput(
                    caseID: caseID.rawValue,
                    reason: "A compound box member has a degenerate dimension."
                )
            }
            let plane = try CADBoxGeometryMapping.sourcePlane(
                submittedOrigin: origin,
                submittedWidth: width,
                submittedDepth: depth,
                caseID: caseID
            )
            return .createExtrudedRectangle(
                name: name,
                plane: SketchPlaneReference(sketchPlane: plane),
                width: .constant(.length(width.meters, unit: .meter)),
                height: .constant(.length(depth.meters, unit: .meter)),
                depth: .constant(.length(height.meters, unit: .meter)),
                direction: .normal
            )

        case let (.cylinder, .cylinder(name, baseCenter, axis, radius, depth)):
            guard !name.isEmpty else {
                throw CADBenchmarkError.invalidInput(
                    caseID: caseID.rawValue,
                    reason: "A compound cylinder member must have a name."
                )
            }
            try baseCenter.validate(caseID: caseID, field: "compound.\(submitted.role).baseCenter")
            try axis.validate(caseID: caseID, field: "compound.\(submitted.role).axis")
            try radius.validate(caseID: caseID, field: "compound.\(submitted.role).radius")
            try depth.validate(caseID: caseID, field: "compound.\(submitted.role).depth")
            let tolerance = try CADBenchmarkTolerancePolicy(modelingTolerance: modelingTolerance)
            guard tolerance.isNonDegenerate(radius.meters),
                  tolerance.isNonDegenerate(depth.meters) else {
                throw CADBenchmarkError.invalidInput(
                    caseID: caseID.rawValue,
                    reason: "A compound cylinder member has a degenerate dimension."
                )
            }
            let geometry = try CADCylinderGeometryMapping.commandGeometry(
                baseCenter: baseCenter,
                axis: axis,
                caseID: caseID
            )
            return .createExtrudedCircle(
                name: name,
                plane: SketchPlaneReference(sketchPlane: geometry.plane),
                center: geometry.localCenter,
                radius: .constant(.length(radius.meters, unit: .meter)),
                depth: .constant(.length(depth.meters, unit: .meter)),
                direction: .normal
            )

        case (.box, .cylinder), (.cylinder, .box):
            throw CADBenchmarkError.invalidInput(
                caseID: caseID.rawValue,
                reason: "A compound member primitive does not match its declared public type."
            )
        }
    }
}
