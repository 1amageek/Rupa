import RupaCore
import Testing
@testable import RupaUI

@Suite("Loft history draft", .timeLimit(.minutes(1)))
struct LoftFeatureDraftTests {
    @Test func profileRegionIndexSurvivesEditingAndRejectsInvalidText() throws {
        let source = LoftSectionReference(profile: ProfileReference(featureID: FeatureID(), profileIndex: 2))
        var draft = LoftSectionDraft(section: source)
        #expect(try draft.applying(to: source) == source)
        draft.profileIndex = " 1 "
        #expect(try draft.applying(to: source).section == .profile(ProfileReference(featureID: source.featureID, profileIndex: 1)))
        for value in ["", "-1", "1.5", "nan", "9999999999999999999999999999"] {
            draft.profileIndex = value
            #expect(throws: EditorError.self) { try draft.applying(to: source) }
        }
    }

    @Test func sectionInsertionRemovalAndReinsertionUseOneReplacement() throws {
        let first = FeatureID()
        let second = FeatureID()
        let third = FeatureID()
        let feature = FeatureNode(operation: .loft(LoftFeature(sections: [
            LoftSectionReference(profile: ProfileReference(featureID: first), smoothTangentScale: 0.4),
            LoftSectionReference(profile: ProfileReference(featureID: second))
        ], options: LoftOptions(resultKind: .sheet))))
        var draft = try #require(LoftFeatureDraft(feature: feature))
        draft.removeSection(first)
        #expect(draft.controls[first] == nil)
        #expect(throws: (any Error).self) { try draft.command() }
        draft.appendSection(.curve(CurveSectionReference(featureID: third, parameterDomain: .closed(0.2, 0.8))))
        guard case .setLoft(let id, let updated) = try draft.command() else {
            Issue.record("Expected a source replacement."); return
        }
        #expect(id == feature.id)
        #expect(updated.sections.map(\.featureID) == [second, third])
        #expect(updated.sections[1].section == .curve(CurveSectionReference(featureID: third, parameterDomain: .closed(0.2, 0.8))))
        draft.appendSection(.profile(ProfileReference(featureID: first)))
        #expect(draft.controls[first]?.tangentScale == "")
        draft.appendSection(.profile(ProfileReference(featureID: second)))
        #expect(throws: (any Error).self) { try draft.command() }
    }

    @Test func defaultTensionEditsPreserveSectionOverridesAndRejectInvalidValues() throws {
        let sections = [
            LoftSectionReference(profile: ProfileReference(featureID: FeatureID())),
            LoftSectionReference(profile: ProfileReference(featureID: FeatureID()), smoothTangentScale: 0.75)
        ]
        let feature = FeatureNode(operation: .loft(LoftFeature(sections: sections,
            options: LoftOptions(surfaceMode: .smooth, smoothTangentScale: 0.6))))
        var draft = try #require(LoftFeatureDraft(feature: feature))
        #expect(draft.defaultTension == "0.6")
        draft.defaultTension = " 1.25 "
        guard case .setLoft(_, let updated) = try draft.command() else {
            Issue.record("Expected a source replacement."); return
        }
        #expect(updated.options.smoothTangentScale == 1.25)
        #expect(updated.sections == sections)
        for value in ["", "0", "-1", "nan", "inf", "1 mm"] {
            draft.defaultTension = value
            #expect(throws: (any Error).self) { try draft.command() }
        }
    }

    @Test func historyGuideEditsUseTheSameSourceReplacement() throws {
        let sections = [FeatureID(), FeatureID()].map { LoftSectionReference(profile: ProfileReference(featureID: $0)) }
        let first = LoftGuideReference(featureID: FeatureID())
        let second = LoftGuideReference(featureID: FeatureID())
        let feature = FeatureNode(operation: .loft(LoftFeature(sections: sections, guides: [first])))
        var draft = try #require(LoftFeatureDraft(feature: feature))
        draft.source.guides.append(second)
        draft.source.guides.reverse()
        guard case .setLoft(let id, let updated) = try draft.command() else {
            Issue.record("Expected a source replacement."); return
        }
        #expect(id == feature.id)
        #expect(updated.guides == [second, first])
        draft.source.guides.removeAll()
        guard case .setLoft(_, let cleared) = try draft.command() else {
            Issue.record("Expected a source replacement."); return
        }
        #expect(cleared.guides.isEmpty)
        draft.source.guides = [LoftGuideReference(featureID: sections[0].featureID)]
        #expect(throws: (any Error).self) { try draft.command() }
    }

    @Test func sectionStartIndexCanBeEditedClearedAndRejectsInvalidText() throws {
        let source = LoftSectionReference(profile: ProfileReference(featureID: FeatureID()), startSampleIndex: 4)
        var draft = LoftSectionDraft(section: source)
        #expect(try draft.applying(to: source).startSampleIndex == 4)
        draft.startSampleIndex = " 2 "
        #expect(try draft.applying(to: source).startSampleIndex == 2)
        draft.startSampleIndex = ""
        #expect(try draft.applying(to: source).startSampleIndex == nil)
        for value in ["-1", "1.5", "nan", "9999999999999999999999999999"] {
            draft.startSampleIndex = value
            #expect(throws: EditorError.self) { try draft.applying(to: source) }
        }
    }

    @Test func unchangedDraftPreservesUnexposedSourceAndEditsFollowReordering() throws {
        let first = FeatureID()
        let second = FeatureID()
        let loft = LoftFeature(sections: [
            LoftSectionReference(section: .curve(CurveSectionReference(featureID: first,
                parameterDomain: .closed(0.01, 0.03), isReversed: true)), smoothTangentScale: 0.7),
            LoftSectionReference(profile: ProfileReference(featureID: second, profileIndex: 2),
                profileDirection: .reversed,
                startSampleIndex: 4, smoothTangentMode: .zero)
        ], guides: [LoftGuideReference(featureID: FeatureID())],
            options: LoftOptions(resultKind: .sheet, surfaceMode: .smooth, smoothTangentScale: 0.6))
        let feature = FeatureNode(name: "Existing Loft", operation: .loft(loft))
        var draft = try #require(LoftFeatureDraft(feature: feature))
        #expect(try draft.command() == .setLoft(featureID: feature.id, loft: loft))
        draft.source.sections.reverse()
        draft.controls[first]?.tangentScale = "1.25"
        draft.controls[first]?.usesCurveInterval = false
        guard case .setLoft(let id, let edited) = try draft.command() else {
            Issue.record("Expected a source replacement."); return
        }
        #expect(id == feature.id)
        #expect(edited.sections[0] == loft.sections[1])
        #expect(edited.sections[1].smoothTangentScale == 1.25)
        #expect(edited.sections[1].section == .curve(CurveSectionReference(featureID: first, isReversed: true)))
        #expect(edited.guides == loft.guides)
        #expect(edited.options == loft.options)
        draft.controls[first]?.upperParameter = "nan"
        draft.controls[first]?.usesCurveInterval = true
        #expect(throws: EditorError.self) { try draft.command() }
    }
}
