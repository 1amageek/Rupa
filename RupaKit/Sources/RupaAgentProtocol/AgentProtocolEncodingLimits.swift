import Foundation
import RupaDomainFoundation

/// Byte ceilings owned by the semantic protocol.
///
/// The transport may impose a lower ceiling.  This value deliberately does
/// not import or depend on a transport module; the application composition
/// validates that the selected protocol limits fit its transport before it
/// starts serving requests.
public struct AgentProtocolEncodingLimits: Sendable, Equatable {
    public static let defaultMaximumByteCount = 16 * 1024 * 1024

    /// Stable identifiers in the project model are bounded by this value.
    public static let maximumStableIdentifierUTF8ByteCount = 1_024

    /// UInt64 and a signed 64-bit integer require at most twenty JSON bytes
    /// for their decimal representation, including the sign when present.
    public static let maximumScalarUTF8ByteCount = 20

    /// The maximum encoded JSON request body accepted by the protocol.
    public let maximumRequestByteCount: Int

    /// The maximum encoded JSON response body accepted by the protocol.
    public let maximumResponseByteCount: Int

    /// The maximum UTF-8 byte count allowed for request/output identifiers
    /// when a response plan reserves variable-length identity fields.
    public let maximumIdentifierUTF8ByteCount: Int

    /// The maximum UTF-8 byte count allowed for the project identity carried
    /// in an authority coordinate.
    public let maximumProjectIDUTF8ByteCount: Int

    /// The maximum number of scalar digits reserved for any encoded counter.
    public let maximumScalarUTF8ByteCount: Int

    public init(
        maximumRequestByteCount: Int = Self.defaultMaximumByteCount,
        maximumResponseByteCount: Int = Self.defaultMaximumByteCount,
        maximumIdentifierUTF8ByteCount: Int = 1_024,
        maximumProjectIDUTF8ByteCount: Int = 1_024,
        maximumScalarUTF8ByteCount: Int = 20
    ) {
        self.maximumRequestByteCount = maximumRequestByteCount
        self.maximumResponseByteCount = maximumResponseByteCount
        self.maximumIdentifierUTF8ByteCount = maximumIdentifierUTF8ByteCount
        self.maximumProjectIDUTF8ByteCount = maximumProjectIDUTF8ByteCount
        self.maximumScalarUTF8ByteCount = maximumScalarUTF8ByteCount
    }

    public func validate() throws {
        let values: [(String, Int)] = [
            ("maximumRequestByteCount", maximumRequestByteCount),
            ("maximumResponseByteCount", maximumResponseByteCount),
            ("maximumIdentifierUTF8ByteCount", maximumIdentifierUTF8ByteCount),
            ("maximumProjectIDUTF8ByteCount", maximumProjectIDUTF8ByteCount),
            ("maximumScalarUTF8ByteCount", maximumScalarUTF8ByteCount)
        ]
        for (name, value) in values where value <= 0 {
            throw AgentResponseEncodingError.invalidLimit(name: name, value: value)
        }
        guard maximumIdentifierUTF8ByteCount <= Self.maximumStableIdentifierUTF8ByteCount else {
            throw AgentResponseEncodingError.invalidLimit(
                name: "maximumIdentifierUTF8ByteCount",
                value: maximumIdentifierUTF8ByteCount
            )
        }
        guard maximumProjectIDUTF8ByteCount <= Self.maximumStableIdentifierUTF8ByteCount else {
            throw AgentResponseEncodingError.invalidLimit(
                name: "maximumProjectIDUTF8ByteCount",
                value: maximumProjectIDUTF8ByteCount
            )
        }
        guard maximumScalarUTF8ByteCount == Self.maximumScalarUTF8ByteCount else {
            throw AgentResponseEncodingError.invalidLimit(
                name: "maximumScalarUTF8ByteCount",
                value: maximumScalarUTF8ByteCount
            )
        }
        guard maximumIdentifierUTF8ByteCount <= maximumResponseByteCount else {
            throw AgentResponseEncodingError.invalidLimit(
                name: "maximumIdentifierUTF8ByteCount",
                value: maximumIdentifierUTF8ByteCount
            )
        }
        guard maximumProjectIDUTF8ByteCount <= maximumResponseByteCount else {
            throw AgentResponseEncodingError.invalidLimit(
                name: "maximumProjectIDUTF8ByteCount",
                value: maximumProjectIDUTF8ByteCount
            )
        }
        let minimumFailureByteCount = try minimumPrepublicationFailureByteCount()
        guard maximumResponseByteCount >= minimumFailureByteCount else {
            throw AgentResponseEncodingError.invalidLimit(
                name: "maximumResponseByteCount",
                value: maximumResponseByteCount
            )
        }
    }

    private func minimumPrepublicationFailureByteCount() throws -> Int {
        let code = DomainCapabilityErrorCode(
            rawValue: String(
                repeating: "\"",
                count: maximumIdentifierUTF8ByteCount
            )
        )
        let methods = ["capability.invoke", "program.execute"]
        var maximum = 0
        for method in methods {
            let response: AgentResponse = switch method {
            case "capability.invoke":
                .capabilityExecution(
                    .prepublicationFailure(
                        AgentSemanticPrepublicationFailure(
                            stage: .responsePlanRejected,
                            code: code
                        )
                    )
                )
            case "program.execute":
                .programExecution(
                    .prepublicationFailure(
                        AgentSemanticPrepublicationFailure(
                            stage: .responsePlanRejected,
                            code: code
                        )
                    )
                )
            default:
                throw AgentResponseEncodingError.unsupportedPlanMethod(method)
            }
            let envelope = AgentResponseEnvelope(
                id: String(
                    repeating: "\"",
                    count: maximumIdentifierUTF8ByteCount
                ),
                response: response,
                method: method
            )
            let byteCount = try JSONEncoder().encode(envelope).count
            maximum = max(maximum, byteCount)
        }
        return maximum
    }
}
