import Foundation
import SwiftCAD

public struct RupaExportPreset: Codable, Hashable, Identifiable, Sendable {
    public enum DestinationPolicy: String, Codable, CaseIterable, Sendable {
        case prompt
        case overwrite
        case versioned
    }

    public var id: RupaExportPresetID
    public var name: String
    public var format: ExchangeFileFormat
    public var outputUnit: LengthDisplayUnit
    public var tessellation: TessellationOptions
    public var validationRuleIDs: [RupaValidationRuleID]
    public var includeMetadata: Bool
    public var destinationPolicy: DestinationPolicy

    public init(
        id: RupaExportPresetID = RupaExportPresetID(),
        name: String,
        format: ExchangeFileFormat,
        outputUnit: LengthDisplayUnit,
        tessellation: TessellationOptions = .standard,
        validationRuleIDs: [RupaValidationRuleID] = [],
        includeMetadata: Bool = true,
        destinationPolicy: DestinationPolicy = .prompt
    ) {
        self.id = id
        self.name = name
        self.format = format
        self.outputUnit = outputUnit
        self.tessellation = tessellation
        self.validationRuleIDs = validationRuleIDs
        self.includeMetadata = includeMetadata
        self.destinationPolicy = destinationPolicy
    }

    public func validate() throws {
        guard !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw RupaDocumentValidationError.invalidProductMetadata("Export preset names must not be empty.")
        }
        guard format.supportsExport else {
            throw RupaDocumentValidationError.invalidProductMetadata("Export preset format must support export.")
        }
        guard Set(validationRuleIDs).count == validationRuleIDs.count else {
            throw RupaDocumentValidationError.invalidProductMetadata(
                "Export preset validation rule references must be unique."
            )
        }
        try tessellation.validate()
    }
}
