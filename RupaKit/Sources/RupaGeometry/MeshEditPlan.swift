import Foundation
import RupaCoreTypes

/// A non-empty ordered declarative Mesh edit plan.
public struct MeshEditPlan: Codable, Equatable, Sendable {
    public let steps: [MeshEditStep]
    public let limits: MeshEditLimits

    public init(
        steps: [MeshEditStep],
        limits: MeshEditLimits = .standard
    ) throws {
        try limits.validate()
        guard !steps.isEmpty else {
            throw MeshEditError(
                code: .emptyPlan,
                message: "Mesh edit plans must contain at least one step."
            )
        }
        guard steps.count <= limits.maxSteps else {
            throw MeshEditError(
                code: .limitExceeded,
                message: "Mesh edit plan step count exceeds its effective limit."
            )
        }

        var seenStepIDs: Set<MeshEditStepID> = []
        for (index, step) in steps.enumerated() {
            guard step.id.isStructurallyValid else {
                throw MeshEditError(
                    code: .invalidStepID,
                    message: "Mesh edit step IDs must be non-empty printable identifiers."
                )
            }
            guard seenStepIDs.insert(step.id).inserted else {
                throw MeshEditError(
                    code: .duplicateStepID,
                    message: "Mesh edit step IDs must be unique."
                )
            }
            try Self.validate(step.operation, at: index, in: steps)
        }

        self.steps = steps
        self.limits = limits
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(
            steps: container.decode([MeshEditStep].self, forKey: .steps),
            limits: container.decode(MeshEditLimits.self, forKey: .limits)
        )
    }

    private static func validate(
        _ operation: MeshEditOperation,
        at index: Int,
        in steps: [MeshEditStep]
    ) throws {
        switch operation {
        case .primitive(let primitive):
            switch primitive {
            case .setVertexPositions(let edits):
                guard !edits.isEmpty else {
                    throw MeshEditError(
                        code: .emptySelection,
                        message: "Position replacement steps must contain at least one vertex."
                    )
                }
                var vertexIDs: Set<MeshVertexID> = []
                for edit in edits {
                    guard vertexIDs.insert(edit.vertexID).inserted else {
                        throw MeshEditError(
                            code: .invalidReference,
                            message: "Position replacement steps cannot repeat a vertex ID."
                        )
                    }
                    do {
                        try edit.position.validate()
                    } catch {
                        throw MeshEditError(
                            code: .nonFiniteValue,
                            message: "Primitive vertex positions must contain finite coordinates."
                        )
                    }
                }

            case .addFace(let vertexIDs):
                guard vertexIDs.count >= 3, Set(vertexIDs).count == vertexIDs.count else {
                    throw MeshEditError(
                        code: .invalidOperationDomain,
                        message: "Primitive face additions require three or more unique vertices."
                    )
                }

            case .deleteFaces(let selector):
                try Self.validate(selector, allowedDomains: [.face], at: index, in: steps)
            }

        case .translateElements(let selector, let offset):
            try Self.validate(
                selector,
                allowedDomains: [.vertex, .edge, .face, .corner],
                at: index,
                in: steps
            )
            try offset.validate()

        case .extrudeFaces(let selector, let offset):
            try Self.validate(selector, allowedDomains: [.face], at: index, in: steps)
            try offset.validate()
            guard !offset.isZero else {
                throw MeshEditError(
                    code: .zeroExtrusionOffset,
                    message: "Face extrusion requires a non-zero offset."
                )
            }
        }
    }

    private static func validate(
        _ selector: MeshElementSelector,
        allowedDomains: Set<GeometryAttributeDomain>,
        at index: Int,
        in steps: [MeshEditStep]
    ) throws {
        switch selector {
        case .explicit(let selection):
            guard Set(selection.elements).count == selection.elements.count else {
                throw MeshEditError(
                    code: .invalidReference,
                    message: "Mesh edit selectors must not repeat element IDs."
                )
            }
            guard !selection.isEmpty else {
                throw MeshEditError(
                    code: .emptySelection,
                    message: "Mesh edit selectors must not be empty."
                )
            }
            guard selection.elements.allSatisfy({ allowedDomains.contains($0.domain) }) else {
                throw MeshEditError(
                    code: .invalidOperationDomain,
                    message: "The selected element domain is not valid for this operation."
                )
            }

        case .output(let stepID, let role):
            guard let referencedIndex = steps.firstIndex(where: { $0.id == stepID }) else {
                throw MeshEditError(
                    code: .missingOutputReference,
                    message: "Mesh edit selector references a missing step output."
                )
            }
            guard referencedIndex < index else {
                throw MeshEditError(
                    code: .forwardOutputReference,
                    message: "Mesh edit selectors may reference only prior steps."
                )
            }
            guard steps[referencedIndex].operation.outputRoles.contains(role) else {
                throw MeshEditError(
                    code: .inapplicableOutputRole,
                    message: "The referenced step does not produce the requested output role."
                )
            }
            guard allowedDomains.contains(role.domain) else {
                throw MeshEditError(
                    code: .invalidOperationDomain,
                    message: "The selected output role is not valid for this operation."
                )
            }
        }
    }

    private enum CodingKeys: String, CodingKey {
        case steps
        case limits
    }
}
