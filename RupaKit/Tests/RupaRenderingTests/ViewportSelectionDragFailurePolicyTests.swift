import Foundation
import RupaCoreTypes
@testable import RupaRendering
import RupaViewportScene
import Testing

private struct UnrelatedSelectionDragFailure: Error, Equatable {
    var reason: String
}

private let refusedSelectionDragCodes: [MeshSourcePresentationRenderError.Code] = [
    .failed,
    .invalidTransform,
    .invalidSceneItem,
    .sourceAuthorityMismatch,
    .resourceExhausted,
    .gpuFailure,
]

@Suite("Viewport selection drag failure policy")
struct ViewportSelectionDragFailurePolicyTests {
    @Test("A resolved rectangle publishes the answer unchanged")
    func publishesResolvedAnswer() throws {
        let target = ViewportSelectionDragTarget(
            hits: [],
            presentationOccurrenceIDs: [SceneOccurrenceID(rawValue: "occurrence")],
            selectionIntent: .toggle
        )
        let outcome = ViewportSelectionDragFailurePolicy.outcome(for: .success(target))
        guard case let .publishes(published) = outcome else {
            Issue.record("A resolved rectangle must publish its answer.")
            return
        }
        #expect(published == target)
    }

    @Test("A frame that has judged nothing retains the previous preview")
    func retainsPreviewForNotReadyFrame() throws {
        let error = MeshSourcePresentationRenderError(
            code: .frameNotReady,
            message: "The native surface query is unavailable before preparation."
        )
        let outcome = ViewportSelectionDragFailurePolicy.outcome(for: .failure(error))
        guard case let .retainsPreview(retained) = outcome else {
            Issue.record("A not-ready frame must retain the previous preview.")
            return
        }
        #expect(retained == error)
    }

    @Test("Every other typed failure is refused", arguments: refusedSelectionDragCodes)
    func refusesEveryOtherRenderCode(code: MeshSourcePresentationRenderError.Code) throws {
        let error = MeshSourcePresentationRenderError(code: code, message: "refused")
        let outcome = ViewportSelectionDragFailurePolicy.outcome(for: .failure(error))
        guard case let .refuses(refused) = outcome else {
            Issue.record("The \(code.rawValue) failure must be refused.")
            return
        }
        #expect(refused as? MeshSourcePresentationRenderError == error)
    }

    @Test("A failure of an unrelated type is refused")
    func refusesUnrelatedErrorType() throws {
        let error = UnrelatedSelectionDragFailure(reason: "unrelated")
        let outcome = ViewportSelectionDragFailurePolicy.outcome(for: .failure(error))
        guard case let .refuses(refused) = outcome else {
            Issue.record("An unrelated failure must be refused.")
            return
        }
        #expect(refused as? UnrelatedSelectionDragFailure == error)
    }

    @Test("A refusal reports the typed code with its message")
    func refusalDescriptionNamesCodeAndMessage() {
        let error = MeshSourcePresentationRenderError(
            code: .failed,
            message: "The native surface query uses a stale camera revision."
        )
        #expect(
            ViewportSelectionDragFailurePolicy.refusalDescription(error)
                == "failed: The native surface query uses a stale camera revision."
        )
    }

    @Test("A refusal of an unrelated type still reports the failure")
    func refusalDescriptionDescribesUnrelatedError() {
        let error = UnrelatedSelectionDragFailure(reason: "unrelated")
        #expect(
            ViewportSelectionDragFailurePolicy.refusalDescription(error)
                == String(describing: error)
        )
    }
}
