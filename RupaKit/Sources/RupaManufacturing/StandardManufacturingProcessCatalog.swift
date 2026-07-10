public struct StandardManufacturingProcessCatalog: ManufacturingProcessCatalog {
    public let defaultProcessID: ManufacturingProcessID
    public let profiles: [ManufacturingProcessProfile]

    public init() {
        self.defaultProcessID = .materialExtrusion
        self.profiles = Self.standardProfiles
    }

    private static let standardProfiles: [ManufacturingProcessProfile] = [
        ManufacturingProcessProfile(
            id: .materialExtrusion,
            name: "Material Extrusion",
            summary: "Deposits material through a nozzle and evaluates angle-limited overhang support.",
            family: .materialExtrusion,
            supportStrategy: .overhangLimited
        ),
        ManufacturingProcessProfile(
            id: .powderBedFusion,
            name: "Powder Bed Fusion",
            summary: "Builds within a powder bed where surrounding powder supports overhangs.",
            family: .powderBedFusion,
            supportStrategy: .surroundingPowder
        ),
        ManufacturingProcessProfile(
            id: .vatPhotopolymerization,
            name: "Vat Photopolymerization",
            summary: "Cures photopolymer in a vat and evaluates angle-limited support requirements.",
            family: .vatPhotopolymerization,
            supportStrategy: .overhangLimited
        ),
    ]
}
