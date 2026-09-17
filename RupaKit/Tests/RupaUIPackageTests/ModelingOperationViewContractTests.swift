import SwiftUI
import Testing
import RupaCore
@testable import RupaUI

@MainActor
@Suite(.timeLimit(.minutes(1)))
struct ModelingOperationViewContractTests {
    @Test func refusalIsDerivedBeforeAnyOperationRuns() {
        var calls = 0
        let document = DesignDocument.empty()
        let cases: [(ModelingOperationDraft.Kind, String?)] = [
            (ModelingOperationDraft.Kind.loft, "Select at least two ordered sketch profiles."),
            (.boolean, "Select target CAD bodies, then a separate tool body last."),
            (.box, nil),
        ]
        for (kind, expected) in cases {
            let draft = ModelingOperationDraft(kind: kind, selection: .init(), ruler: .standard(for: .millimeter))
            let panel = ModelingOperationView(draft: .constant(draft), document: document,
                isBusy: false, hasMatchingPreview: false, errorMessage: nil,
                onUseSelection: { calls += 1 }, onPreview: { calls += 1 },
                onApply: { calls += 1 }, onCancel: { calls += 1 })
            #expect(panel.planningRefusal == expected)
            _ = panel.body
            #expect(calls == 0)
        }
    }
}
