import Foundation
import SwiftCAD

public struct RupaTemplateDefaults: Codable, Hashable, Sendable {
    public var displayUnit: LengthDisplayUnit
    public var ruler: RulerConfiguration
    public var visiblePanelIDs: [String]
    public var validationRuleIDs: [RupaValidationRuleID]
    public var exportPresetIDs: [RupaExportPresetID]
    public var defaultMaterialID: MaterialID?

    public init(
        displayUnit: LengthDisplayUnit = .millimeter,
        ruler: RulerConfiguration = .standard(for: .millimeter),
        visiblePanelIDs: [String] = [],
        validationRuleIDs: [RupaValidationRuleID] = [],
        exportPresetIDs: [RupaExportPresetID] = [],
        defaultMaterialID: MaterialID? = nil
    ) {
        self.displayUnit = displayUnit
        self.ruler = ruler
        self.visiblePanelIDs = visiblePanelIDs
        self.validationRuleIDs = validationRuleIDs
        self.exportPresetIDs = exportPresetIDs
        self.defaultMaterialID = defaultMaterialID
    }

    public func validate() throws {
        try ruler.validate()
        guard ruler.displayUnit == displayUnit else {
            throw RupaDocumentValidationError.invalidProductMetadata(
                "Template ruler display unit must match the template display unit."
            )
        }
        guard Set(visiblePanelIDs).count == visiblePanelIDs.count else {
            throw RupaDocumentValidationError.invalidProductMetadata("Visible panel IDs must be unique.")
        }
        for panelID in visiblePanelIDs {
            guard !panelID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw RupaDocumentValidationError.invalidProductMetadata("Visible panel IDs must not be empty.")
            }
        }
        guard Set(validationRuleIDs).count == validationRuleIDs.count else {
            throw RupaDocumentValidationError.invalidProductMetadata(
                "Template validation rule references must be unique."
            )
        }
        guard Set(exportPresetIDs).count == exportPresetIDs.count else {
            throw RupaDocumentValidationError.invalidProductMetadata(
                "Template export preset references must be unique."
            )
        }
    }
}
