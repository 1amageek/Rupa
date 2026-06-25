import SwiftCAD

public struct SweepSelectionPreview: Equatable, Sendable {
    public enum Status: String, Equatable, Sendable {
        case ready
        case missingSection
        case missingPath
        case invalid
    }

    public var status: Status
    public var section: SweepSectionReference?
    public var pathFeatureID: FeatureID?
    public var guideFeatureIDs: [FeatureID]
    public var message: String

    public var profileFeatureID: FeatureID? {
        section?.profile?.featureID
    }

    public var sectionFeatureID: FeatureID? {
        section?.featureID
    }

    public init(
        status: Status,
        section: SweepSectionReference? = nil,
        profileFeatureID: FeatureID? = nil,
        pathFeatureID: FeatureID? = nil,
        guideFeatureIDs: [FeatureID] = [],
        message: String
    ) {
        self.status = status
        self.section = section ?? profileFeatureID.map {
            .profile(ProfileReference(featureID: $0))
        }
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
        case .missingSection:
            "Missing Section"
        case .missingPath:
            "Missing Path"
        case .invalid:
            "Invalid"
        }
    }
}
