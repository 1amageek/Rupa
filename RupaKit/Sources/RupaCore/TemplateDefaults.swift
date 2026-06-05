import Foundation
import SwiftCAD

public struct TemplateDefaults: Codable, Hashable, Sendable {
    public var displayUnit: LengthDisplayUnit
    public var ruler: RulerConfiguration
    public var visiblePanelIDs: [String]
    public var validationRuleIDs: [ValidationRuleID]
    public var exportPresetIDs: [ExportPresetID]
    public var defaultMaterialID: MaterialID?

    public init(
        displayUnit: LengthDisplayUnit = .millimeter,
        ruler: RulerConfiguration = .standard(for: .millimeter),
        visiblePanelIDs: [String] = [],
        validationRuleIDs: [ValidationRuleID] = [],
        exportPresetIDs: [ExportPresetID] = [],
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
            throw DocumentValidationError.invalidProductMetadata(
                "Template ruler display unit must match the template display unit."
            )
        }
        guard Set(visiblePanelIDs).count == visiblePanelIDs.count else {
            throw DocumentValidationError.invalidProductMetadata("Visible panel IDs must be unique.")
        }
        for panelID in visiblePanelIDs {
            guard !panelID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw DocumentValidationError.invalidProductMetadata("Visible panel IDs must not be empty.")
            }
        }
        guard Set(validationRuleIDs).count == validationRuleIDs.count else {
            throw DocumentValidationError.invalidProductMetadata(
                "Template validation rule references must be unique."
            )
        }
        guard Set(exportPresetIDs).count == exportPresetIDs.count else {
            throw DocumentValidationError.invalidProductMetadata(
                "Template export preset references must be unique."
            )
        }
    }
}
