import Foundation
import RupaCore

struct LoftFeatureDraft: Identifiable {
    let id: FeatureID
    let title: String
    var source: LoftFeature
    var defaultTension: String
    var controls: [FeatureID: LoftSectionDraft]

    init?(feature: FeatureNode) {
        guard case .loft(let loft) = feature.operation else { return nil }
        id = feature.id
        title = feature.name ?? "Loft"
        source = loft
        defaultTension = String(loft.options.smoothTangentScale)
        controls = [:]
        for section in loft.sections {
            controls[section.featureID] = LoftSectionDraft(section: section)
        }
    }

    mutating func appendSection(_ reference: SectionReference) {
        let section = LoftSectionReference(section: reference)
        source.sections.append(section)
        controls[section.featureID] = LoftSectionDraft(section: section)
    }

    mutating func removeSection(_ featureID: FeatureID) {
        source.sections.removeAll { $0.featureID == featureID }
        controls.removeValue(forKey: featureID)
    }

    func command() throws -> EditorCommand {
        var updated = source
        guard let tension = Double(defaultTension.trimmingCharacters(in: .whitespacesAndNewlines)) else {
            throw EditorError(code: .commandInvalid, message: "Default section tension must be a positive finite number.")
        }
        updated.options.smoothTangentScale = tension
        updated.sections = try source.sections.map { section in
            guard let controls = controls[section.featureID] else {
                throw EditorError(code: .commandInvalid, message: "Loft section controls are missing.")
            }
            return try controls.applying(to: section)
        }
        try updated.validate()
        return .setLoft(featureID: id, loft: updated)
    }
}
