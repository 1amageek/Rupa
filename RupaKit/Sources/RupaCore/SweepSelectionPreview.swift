import SwiftCAD

public struct SweepSelectionPreview: Equatable, Sendable {
    public enum Status: String, Equatable, Sendable {
        case ready
        case missingProfile
        case missingPath
        case invalid
    }

    public var status: Status
    public var profileFeatureID: FeatureID?
    public var pathFeatureID: FeatureID?
    public var guideFeatureIDs: [FeatureID]
    public var message: String

    public init(
        status: Status,
        profileFeatureID: FeatureID? = nil,
        pathFeatureID: FeatureID? = nil,
        guideFeatureIDs: [FeatureID] = [],
        message: String
    ) {
        self.status = status
        self.profileFeatureID = profileFeatureID
        self.pathFeatureID = pathFeatureID
        self.guideFeatureIDs = guideFeatureIDs
        self.message = message
    }

    public var isReady: Bool {
        status == .ready
    }

    public var statusTitle: String {
        switch status {
        case .ready:
            "Ready"
        case .missingProfile:
            "Missing Profile"
        case .missingPath:
            "Missing Path"
        case .invalid:
            "Invalid"
        }
    }
}
