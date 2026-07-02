import RupaCore

extension WorkspaceScalePreset {
    var compactWorkspaceTitle: String {
        switch self {
        case .microFabrication:
            "Micro"
        case .precisionMechanical:
            "Precision"
        case .productDesign:
            "Product"
        case .roomInterior:
            "Room"
        case .architecture:
            "Arch"
        case .architectureImperial:
            "Arch ft"
        case .sitePlanning:
            "Site"
        case .regionalPlanning:
            "Region"
        case .sitePlanningImperial:
            "Site ft"
        }
    }
}
