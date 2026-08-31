import Foundation
import RupaCore
import RupaDomainFoundation
import RupaKit

public struct AgentMessageCodec {
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder
    public let limits: AgentProtocolEncodingLimits

    public init(
        encoder: JSONEncoder = JSONEncoder(),
        decoder: JSONDecoder = JSONDecoder(),
        limits: AgentProtocolEncodingLimits = AgentProtocolEncodingLimits()
    ) {
        self.encoder = encoder
        self.decoder = decoder
        self.limits = limits
    }

    public func encode(_ request: AgentRequest, id: String = UUID().uuidString) throws -> Data {
        try encode(AgentRequestEnvelope(id: id, params: request))
    }

    public func encode(_ envelope: AgentRequestEnvelope) throws -> Data {
        try limits.validate()
        try envelope.validate()
        try validateCorrelatableIdentifier(envelope.id, name: "requestID")
        let data = try encoder.encode(envelope)
        guard data.count <= limits.maximumRequestByteCount else {
            throw AgentResponseEncodingError.requestTooLarge(
                actual: data.count,
                maximum: limits.maximumRequestByteCount
            )
        }
        return data
    }

    public func encode(
        _ response: AgentResponse,
        id: String? = nil,
        method: String? = nil
    ) throws -> Data {
        try encode(AgentResponseEnvelope(id: id, response: response, method: method))
    }

    public func encode(_ envelope: AgentResponseEnvelope) throws -> Data {
        try limits.validate()
        try envelope.validate()
        try validateCorrelatableIdentifier(envelope.id, name: "responseID")
        try Self.requireUnplannedResponseIsNotSemantic(
            try envelope.decodedResponse(),
            method: envelope.method
        )
        let data = try encoder.encode(envelope)
        guard data.count <= limits.maximumResponseByteCount else {
            throw AgentResponseEncodingError.responseTooLarge(
                actual: data.count,
                maximum: limits.maximumResponseByteCount
            )
        }
        return data
    }

    /// Creates the single-use response reservation required before a semantic
    /// request is staged by the project authority. The plan remains available
    /// for inspection through the returned owner; callers cannot create a
    /// second reservation from that plan.
    package func reserveResponse(
        requestID: String,
        method: String,
        authority: AgentProjectAuthorityCoordinate,
        requestedOutputs: [AgentSemanticOutputReference],
        resultCharge: SemanticResultCharge
    ) throws -> AgentResponseEncodingReservation {
        let failureOnlyPlan = try AgentResponseEncodingPlan.failureOnly(
            requestID: requestID,
            method: method,
            authority: authority,
            requestedOutputs: requestedOutputs,
            resultCharge: resultCharge,
            limits: limits
        )
        do {
            let plan = try AgentResponseEncodingPlan(
                requestID: requestID,
                method: method,
                authority: authority,
                requestedOutputs: requestedOutputs,
                resultCharge: resultCharge,
                limits: limits
            )
            return AgentResponseEncodingReservation(plan: plan)
        } catch let error as AgentResponseEncodingError {
            switch error {
            case .invalidLimit,
                 .unsupportedPlanMethod:
                throw error
            default:
                return AgentResponseEncodingReservation(plan: failureOnlyPlan)
            }
        }
    }

    /// Encodes a planned semantic response exactly once at this boundary.
    /// There is deliberately no generic-error retry when the final response
    /// exceeds a plan: the plan is rejected as an invariant violation.
    func encode(
        _ response: AgentResponse,
        using plan: AgentResponseEncodingPlan
    ) throws -> Data {
        try limits.validate()
        guard plan.limits == limits else {
            throw AgentResponseEncodingError.invalidPlan(
                "The response plan was created with different protocol limits."
            )
        }
        try plan.validate(response: response)
        let envelope = try plan.envelope(for: response)
        let data = try encoder.encode(envelope)
        guard data.count <= plan.reservedEncodedByteCount else {
            throw AgentResponseEncodingError.responseShapeExceedsPlan(
                actual: data.count,
                reserved: plan.reservedEncodedByteCount
            )
        }
        guard data.count <= limits.maximumResponseByteCount else {
            throw AgentResponseEncodingError.responseTooLarge(
                actual: data.count,
                maximum: limits.maximumResponseByteCount
            )
        }
        return data
    }

    /// Takes ownership of a reservation and performs its single encode
    /// attempt. The reservation is marked consumed before encoding so a
    /// failure cannot be retried with a different response after publication.
    package func encode(
        _ response: AgentResponse,
        consuming reservation: AgentResponseEncodingReservation
    ) throws -> Data {
        let plan = try reservation.consume()
        return try encode(response, using: plan)
    }

    public func decodeRequestEnvelope(from data: Data) throws -> AgentRequestEnvelope {
        try limits.validate()
        guard data.count <= limits.maximumRequestByteCount else {
            throw AgentResponseEncodingError.requestTooLarge(
                actual: data.count,
                maximum: limits.maximumRequestByteCount
            )
        }
        let envelope = try decoder.decode(AgentRequestEnvelope.self, from: data)
        try envelope.validate()
        try validateCorrelatableIdentifier(envelope.id, name: "requestID")
        return envelope
    }

    public func decodeRequest(from data: Data) throws -> AgentRequest {
        try decodeRequestEnvelope(from: data).params
    }

    public func decodeResponseEnvelope(from data: Data) throws -> AgentResponseEnvelope {
        try limits.validate()
        guard data.count <= limits.maximumResponseByteCount else {
            throw AgentResponseEncodingError.responseTooLarge(
                actual: data.count,
                maximum: limits.maximumResponseByteCount
            )
        }
        let envelope = try decoder.decode(AgentResponseEnvelope.self, from: data)
        try envelope.validate()
        try validateCorrelatableIdentifier(envelope.id, name: "responseID")
        try Self.requireSemanticMethodDoesNotUseGenericError(envelope)
        return envelope
    }

    public func decodeResponse(from data: Data) throws -> AgentResponse {
        try decodeResponseEnvelope(from: data).decodedResponse()
    }

    public func decodeResponse(from data: Data, expectedID: String) throws -> AgentResponse {
        try decodeResponse(from: data, expectedID: expectedID, expectedMethod: nil)
    }

    public func decodeResponse(
        from data: Data,
        expectedID: String,
        expectedMethod: String?
    ) throws -> AgentResponse {
        let envelope = try decodeResponseEnvelope(from: data)
        guard envelope.id == expectedID else {
            throw EditorError(
                code: .agentConnectionFailed,
                message: "Agent response id mismatch. Expected \(expectedID), received \(envelope.id ?? "nil")."
            )
        }
        if let expectedMethod, envelope.method != expectedMethod {
            throw EditorError(
                code: .agentConnectionFailed,
                message: "Agent response method mismatch. Expected \(expectedMethod), received \(envelope.method ?? "nil")."
            )
        }
        return try envelope.decodedResponse()
    }

    private static func requireUnplannedResponseIsNotSemantic(
        _ response: AgentResponse,
        method: String?
    ) throws {
        if let method, method == "capability.invoke" || method == "program.execute" {
            throw AgentResponseEncodingError.responsePlanRequired(
                method: method
            )
        }
        switch response {
        case .capabilityExecution:
            throw AgentResponseEncodingError.responsePlanRequired(
                method: "capability.invoke"
            )
        case .programExecution:
            throw AgentResponseEncodingError.responsePlanRequired(
                method: "program.execute"
            )
        default:
            return
        }
    }

    private static func requireSemanticMethodDoesNotUseGenericError(
        _ envelope: AgentResponseEnvelope
    ) throws {
        guard envelope.error != nil,
              let method = envelope.method,
              method == "capability.invoke" || method == "program.execute" else {
            return
        }
        throw AgentResponseEncodingError.responsePlanRequired(method: method)
    }

    private func validateCorrelatableIdentifier(
        _ value: String?,
        name: String
    ) throws {
        guard let value else { return }
        guard !value.isEmpty,
              value.trimmingCharacters(in: .whitespacesAndNewlines) == value,
              value.unicodeScalars.allSatisfy({
                  !CharacterSet.controlCharacters.contains($0)
              }) else {
            throw AgentResponseEncodingError.invalidIdentifier(name: name)
        }
        guard value.utf8.count <= limits.maximumIdentifierUTF8ByteCount else {
            throw AgentResponseEncodingError.identifierTooLarge(
                name: name,
                actual: value.utf8.count,
                maximum: limits.maximumIdentifierUTF8ByteCount
            )
        }
    }
}
