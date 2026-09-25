import SwiftCAD
import Testing
@testable import RupaCore

@Test func patternArrayRemapsBothBridgeBoundarySources() throws {
    let first = FeatureID()
    let second = FeatureID()
    let copiedFirst = FeatureID()
    let copiedSecond = FeatureID()
    let signature = try SubshapeGeometrySignature.lineEdge(
        startPoint: .origin, endPoint: Point3D(x: 1, y: 0, z: 0)
    )
    let bridge = BridgeSurfaceFeature(
        startBoundary: StableSubshapeReference(
            subshapeID: SubshapeID(featureID: first, role: "edge", ordinal: 2), geometrySignature: signature
        ),
        endBoundary: StableSubshapeReference(
            subshapeID: SubshapeID(featureID: second, role: "edge", ordinal: 3), geometrySignature: signature
        ),
        endOrientation: .reversed
    )
    let remapper = PatternArrayFeatureIDRemapper(featureIDMap: [first: copiedFirst, second: copiedSecond])
    guard case let .bridgeSurface(result) = try remapper.remappedOperation(.bridgeSurface(bridge)) else {
        Issue.record("Expected the source-linked Bridge operation.")
        return
    }
    #expect(result.startBoundary.subshapeID == SubshapeID(featureID: copiedFirst, role: "edge", ordinal: 2))
    #expect(result.endBoundary.subshapeID == SubshapeID(featureID: copiedSecond, role: "edge", ordinal: 3))
    #expect(result.startBoundary.geometrySignature == signature)
    #expect(result.endBoundary.geometrySignature == signature)
    #expect(result.endOrientation == .reversed)
    #expect(throws: EditorError.self) {
        _ = try PatternArrayFeatureIDRemapper(featureIDMap: [first: copiedFirst])
            .remappedOperation(.bridgeSurface(bridge))
    }
}

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
