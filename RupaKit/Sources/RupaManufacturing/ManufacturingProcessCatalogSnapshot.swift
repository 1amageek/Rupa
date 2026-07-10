public struct ManufacturingProcessCatalogSnapshot: ManufacturingProcessCatalog {
    public let defaultProcessID: ManufacturingProcessID
    public let profiles: [ManufacturingProcessProfile]

    public init(
        defaultProcessID: ManufacturingProcessID,
        profiles: [ManufacturingProcessProfile]
    ) throws {
        self.defaultProcessID = defaultProcessID
        self.profiles = profiles.sorted { $0.id.rawValue < $1.id.rawValue }
        try validate()
    }
}
