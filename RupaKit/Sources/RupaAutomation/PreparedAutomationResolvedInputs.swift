import SwiftCAD
import RupaCore

/// Typed inputs made available to one prepared command builder.
public struct PreparedAutomationResolvedInputs: Sendable {
    private let values: [PreparedAutomationSlotID: PreparedAutomationIdentity]

    init(values: [PreparedAutomationSlotID: PreparedAutomationIdentity]) {
        self.values = values
    }

    public func identity(
        for slotID: PreparedAutomationSlotID
    ) throws -> PreparedAutomationIdentity {
        guard let value = values[slotID] else {
            throw PreparedAutomationInputResolutionError.missing(slotID)
        }
        return value
    }

    public func featureID(
        for slotID: PreparedAutomationSlotID
    ) throws -> FeatureID {
        try typedValue(for: slotID, expected: .feature) { identity in
            guard case .feature(let id) = identity else { return nil }
            return id
        }
    }

    public func sourceBody(
        for slotID: PreparedAutomationSlotID
    ) throws -> (featureID: FeatureID, role: SourceBodyOutputRole) {
        let identity = try identity(for: slotID)
        guard case .sourceBody(let featureID, let role) = identity else {
            throw PreparedAutomationInputResolutionError.kindMismatch(
                slotID: slotID,
                expected: .sourceBody(role: .body),
                actual: identity.kind
            )
        }
        return (featureID, role)
    }

    public func sceneNodeID(
        for slotID: PreparedAutomationSlotID
    ) throws -> SceneNodeID {
        try typedValue(for: slotID, expected: .sceneNode) { identity in
            guard case .sceneNode(let id) = identity else { return nil }
            return id
        }
    }

    public func componentDefinitionID(
        for slotID: PreparedAutomationSlotID
    ) throws -> ComponentDefinitionID {
        try typedValue(for: slotID, expected: .componentDefinition) { identity in
            guard case .componentDefinition(let id) = identity else { return nil }
            return id
        }
    }

    public func componentInstanceID(
        for slotID: PreparedAutomationSlotID
    ) throws -> ComponentInstanceID {
        try typedValue(for: slotID, expected: .componentInstance) { identity in
            guard case .componentInstance(let id) = identity else { return nil }
            return id
        }
    }

    public func patternArraySourceID(
        for slotID: PreparedAutomationSlotID
    ) throws -> PatternArraySourceID {
        try typedValue(for: slotID, expected: .patternArraySource) { identity in
            guard case .patternArraySource(let id) = identity else { return nil }
            return id
        }
    }

    private func typedValue<Value>(
        for slotID: PreparedAutomationSlotID,
        expected: PreparedAutomationIdentityKind,
        _ projection: (PreparedAutomationIdentity) -> Value?
    ) throws -> Value {
        let identity = try identity(for: slotID)
        guard let value = projection(identity) else {
            throw PreparedAutomationInputResolutionError.kindMismatch(
                slotID: slotID,
                expected: expected,
                actual: identity.kind
            )
        }
        return value
    }
}
