import SwiftCAD
import Testing
@testable import RupaCore

@Test func patternArrayFeatureIDRemapperPreservesLoftSectionTangentControls() throws {
    let originalFirstProfileID = FeatureID()
    let originalSecondProfileID = FeatureID()
    let remappedFirstProfileID = FeatureID()
    let remappedSecondProfileID = FeatureID()
    let remapper = PatternArrayFeatureIDRemapper(featureIDMap: [
        originalFirstProfileID: remappedFirstProfileID,
        originalSecondProfileID: remappedSecondProfileID,
    ])
    let operation = FeatureOperation.loft(LoftFeature(
        sections: [
            LoftSectionReference(
                profile: ProfileReference(featureID: originalFirstProfileID),
                startSampleIndex: 2,
                smoothTangentScale: 0.5,
                smoothTangentMode: .zero
            ),
            LoftSectionReference(
                profile: ProfileReference(featureID: originalSecondProfileID),
                smoothTangentMode: .automatic
            ),
        ],
        options: LoftOptions(surfaceMode: .smooth)
    ))

    guard case .loft(let remappedLoft) = try remapper.remappedOperation(operation) else {
        Issue.record("Expected remapped Loft operation.")
        return
    }

    #expect(remappedLoft.sections[0].profile.featureID == remappedFirstProfileID)
    #expect(remappedLoft.sections[0].startSampleIndex == 2)
    #expect(remappedLoft.sections[0].smoothTangentScale == 0.5)
    #expect(remappedLoft.sections[0].smoothTangentMode == .zero)
    #expect(remappedLoft.sections[1].profile.featureID == remappedSecondProfileID)
    #expect(remappedLoft.sections[1].smoothTangentMode == .automatic)
}
