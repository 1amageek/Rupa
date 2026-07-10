import Foundation
import RupaCore

public struct DomainCommandPayloadBuilder: Sendable {
    public init() {}

    public func defaultValues(
        for descriptor: DomainCapabilityDescriptor
    ) -> [String: SemanticJSONValue] {
        var values: [String: SemanticJSONValue] = [:]
        for parameter in descriptor.parameters {
            if let defaultValue = parameter.defaultValue {
                values[parameter.id] = defaultValue
            }
        }
        return values
    }

    public func payload(
        for descriptor: DomainCapabilityDescriptor,
        values: [String: SemanticJSONValue]
    ) throws -> SemanticJSONValue {
        do {
            try descriptor.validate()
        } catch {
            throw DomainCommandPayloadError(
                code: .invalidDescriptor,
                message: "Domain capability \(descriptor.id.rawValue) has an invalid parameter contract: \(error.localizedDescription)"
            )
        }

        let knownParameterIDs = Set(descriptor.parameters.map(\.id))
        let unknownParameterIDs = values.keys.filter { !knownParameterIDs.contains($0) }.sorted()
        guard unknownParameterIDs.isEmpty else {
            throw DomainCommandPayloadError(
                code: .unknownParameter,
                parameterID: unknownParameterIDs.first,
                message: "Domain capability \(descriptor.id.rawValue) received unknown parameter(s): \(unknownParameterIDs.joined(separator: ", "))."
            )
        }

        guard !descriptor.parameters.isEmpty else {
            return .null
        }

        var payloadObject: [String: SemanticJSONValue] = [:]
        for parameter in descriptor.parameters {
            let value = values[parameter.id] ?? parameter.defaultValue
            guard let value else {
                guard !parameter.isRequired else {
                    throw DomainCommandPayloadError(
                        code: .missingValue,
                        parameterID: parameter.id,
                        message: "Required domain command parameter \(parameter.id) is missing."
                    )
                }
                continue
            }
            try parameter.validateValue(value)
            payloadObject = Self.setting(
                value,
                at: parameter.payloadPath[...],
                in: payloadObject
            )
        }
        return .object(payloadObject)
    }

    private static func setting(
        _ value: SemanticJSONValue,
        at path: ArraySlice<String>,
        in object: [String: SemanticJSONValue]
    ) -> [String: SemanticJSONValue] {
        guard let key = path.first else {
            return object
        }
        var updated = object
        let remainingPath = path.dropFirst()
        guard !remainingPath.isEmpty else {
            updated[key] = value
            return updated
        }

        let nestedObject: [String: SemanticJSONValue]
        if case .some(.object(let currentObject)) = updated[key] {
            nestedObject = currentObject
        } else {
            nestedObject = [:]
        }
        updated[key] = .object(
            setting(value, at: remainingPath, in: nestedObject)
        )
        return updated
    }
}
