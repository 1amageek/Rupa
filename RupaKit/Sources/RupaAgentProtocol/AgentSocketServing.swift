/// Extends request handling with the endpoint state required by a socket host.
public protocol AgentSocketServing: AgentRequestHandling {
    func setSocketPath(_ path: String?) async
}
