public struct DesignProcessDecisionRecord: Codable, Equatable, Sendable {
    public var id: String
    public var conflictArea: String
    public var selectedRouteID: String
    public var rejectedRouteIDs: [String]
    public var rationale: String
    public var followUpOwner: DesignProcessLayer?

    public init(
        id: String,
        conflictArea: String,
        selectedRouteID: String,
        rejectedRouteIDs: [String] = [],
        rationale: String,
        followUpOwner: DesignProcessLayer? = nil
    ) {
        self.id = id
        self.conflictArea = conflictArea
        self.selectedRouteID = selectedRouteID
        self.rejectedRouteIDs = rejectedRouteIDs
        self.rationale = rationale
        self.followUpOwner = followUpOwner
    }
}
