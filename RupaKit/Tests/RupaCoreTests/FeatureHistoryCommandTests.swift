import RupaCore
import SwiftCAD
import Testing

@Test(.timeLimit(.minutes(1)))
func featureHistoryReorderValidatesDependenciesAndParticipatesInUndoRedo() throws {
    let (store, commandStack) = try makeIndependentFeatureHistoryFixture()
    let originalOrder = store.document.cadDocument.designGraph.order

    let noOp = try commandStack.execute(
        .reorderFeatureGraph(featureIDs: originalOrder),
        in: store
    )
    #expect(!noOp.didMutate)
    #expect(store.document.cadDocument.designGraph.order == originalOrder)
    #expect(commandStack.undoEntries.count == 2)

    let reordered = Array(originalOrder.reversed())
    let result = try commandStack.execute(
        .reorderFeatureGraph(featureIDs: reordered),
        in: store
    )
    #expect(result.commandName == "reorderFeatureGraph")
    #expect(result.didMutate)
    #expect(store.document.cadDocument.designGraph.order == reordered)
    #expect(commandStack.undoEntries.count == 3)

    _ = try commandStack.undo(in: store)
    #expect(store.document.cadDocument.designGraph.order == originalOrder)
    _ = try commandStack.redo(in: store)
    #expect(store.document.cadDocument.designGraph.order == reordered)
}

@Test(.timeLimit(.minutes(1)))
func featureHistoryRejectsDependencyUnsafeReorderWithoutMutation() throws {
    let (store, commandStack) = try makeDependentFeatureHistoryFixture()
    let originalOrder = store.document.cadDocument.designGraph.order
    let bodyID = try #require(originalOrder.last)
    let profileID = try #require(originalOrder.first)
    let generation = store.generation
    let historyCount = commandStack.undoEntries.count

    do {
        _ = try commandStack.execute(
            .reorderFeatureGraph(featureIDs: [bodyID, profileID]),
            in: store,
            expectedGeneration: generation
        )
        Issue.record("Expected dependency-unsafe feature reorder to fail.")
    } catch FeatureEvaluationError.invalidGraph(let message) {
        #expect(message.contains("dependency") || message.contains("input"))
    } catch {
        Issue.record("Expected invalidGraph, got \(error).")
    }

    #expect(store.document.cadDocument.designGraph.order == originalOrder)
    #expect(store.generation == generation)
    #expect(commandStack.undoEntries.count == historyCount)
    #expect(store.evaluationStatus == .valid)
}

private func makeIndependentFeatureHistoryFixture() throws -> (
    store: CADDocumentStore,
    commandStack: CommandStack
) {
    let store = CADDocumentStore()
    let commandStack = CommandStack()
    _ = try commandStack.execute(
        .createRectangleSketch(
            name: "First",
            plane: .xy,
            width: .length(8.0, .millimeter),
            height: .length(4.0, .millimeter)
        ),
        in: store
    )
    _ = try commandStack.execute(
        .createRectangleSketch(
            name: "Second",
            plane: .xy,
            width: .length(6.0, .millimeter),
            height: .length(3.0, .millimeter)
        ),
        in: store
    )
    return (store, commandStack)
}

private func makeDependentFeatureHistoryFixture() throws -> (
    store: CADDocumentStore,
    commandStack: CommandStack
) {
    let store = CADDocumentStore()
    let commandStack = CommandStack()
    _ = try commandStack.execute(
        .createRectangleSketch(
            name: "Profile",
            plane: .xy,
            width: .length(8.0, .millimeter),
            height: .length(4.0, .millimeter)
        ),
        in: store
    )
    let profileID = try #require(store.document.cadDocument.designGraph.order.first)
    _ = try commandStack.execute(
        .extrudeProfile(
            name: "Body",
            profile: ProfileReference(featureID: profileID),
            distance: .length(2.0, .millimeter),
            direction: .normal
        ),
        in: store
    )
    return (store, commandStack)
}
