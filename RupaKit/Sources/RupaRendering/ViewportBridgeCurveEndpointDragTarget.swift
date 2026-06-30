import RupaCore

public struct ViewportBridgeCurveEndpointDragTarget: Equatable, Sendable {
    public var sourceID: BridgeCurveSourceID
    public var role: BridgeCurveEndpointHandleRole
    public var endpoint: BridgeCurveEndpoint

    public init(
        sourceID: BridgeCurveSourceID,
        role: BridgeCurveEndpointHandleRole,
        endpoint: BridgeCurveEndpoint
    ) {
        self.sourceID = sourceID
        self.role = role
        self.endpoint = endpoint
    }
}
