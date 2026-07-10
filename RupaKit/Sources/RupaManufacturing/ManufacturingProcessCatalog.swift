public protocol ManufacturingProcessCatalog: Sendable {
    var defaultProcessID: ManufacturingProcessID { get }
    var profiles: [ManufacturingProcessProfile] { get }

    func profile(for id: ManufacturingProcessID) -> ManufacturingProcessProfile?
}

public extension ManufacturingProcessCatalog {
    func profile(for id: ManufacturingProcessID) -> ManufacturingProcessProfile? {
        profiles.first { $0.id == id }
    }

    func validate() throws {
        guard !profiles.isEmpty else {
            throw ManufacturingProcessCatalogError(
                code: .missingDefaultProcess,
                message: "Manufacturing process catalogs must contain at least one profile."
            )
        }
        for profile in profiles {
            try profile.validate()
        }
        guard Set(profiles.map(\.id)).count == profiles.count else {
            throw ManufacturingProcessCatalogError(
                code: .duplicateProcess,
                message: "Manufacturing process catalogs must not contain duplicate process IDs."
            )
        }
        guard profile(for: defaultProcessID) != nil else {
            throw ManufacturingProcessCatalogError(
                code: .missingDefaultProcess,
                message: "The default manufacturing process must reference a catalog profile."
            )
        }
    }
}
