import Foundation

public struct ManufacturingProcessProfile: Codable, Equatable, Sendable {
    public var id: ManufacturingProcessID
    public var name: String
    public var summary: String
    public var family: ManufacturingProcessFamily
    public var supportStrategy: ManufacturingSupportStrategy

    public init(
        id: ManufacturingProcessID,
        name: String,
        summary: String,
        family: ManufacturingProcessFamily,
        supportStrategy: ManufacturingSupportStrategy
    ) {
        self.id = id
        self.name = name
        self.summary = summary
        self.family = family
        self.supportStrategy = supportStrategy
    }

    public func validate() throws {
        try id.validate()
        guard !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw ManufacturingProcessCatalogError(
                code: .invalidProfile,
                message: "Manufacturing process profile names must not be empty."
            )
        }
        guard !summary.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw ManufacturingProcessCatalogError(
                code: .invalidProfile,
                message: "Manufacturing process profile summaries must not be empty."
            )
        }
    }
}
