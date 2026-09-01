/// A transport-neutral response returned by an Agent request handler.
///
/// Ordinary methods are encoded by the transport with the request envelope's
/// correlation fields. Semantic methods carry the single-use reservation made
/// before project staging and therefore cannot use ordinary encoding.
public enum AgentHandledResponse: Sendable {
    case ordinary(AgentResponse)
    case planned(
        response: AgentResponse,
        reservation: AgentResponseEncodingReservation
    )
}
