import RupaCore
import Testing
@testable import RupaUI

@Test func measurementGateDrawsBoundsRulersOnlyForTheMeasureTool() {
    for tool in ModelingTool.allCases {
        #expect(WorkspaceMeasurementPresentationGate.showsBoundsRulers(
            selectedTool: tool,
            hasOwningInteraction: false
        ) == (tool == .measure))
    }
}

@Test func measurementGateShowsSelectReadoutOnlyInObjectScope() {
    for scope in WorkspaceSelectionScope.allCases {
        #expect(WorkspaceMeasurementPresentationGate.showsBoundsReadout(
            selectedTool: .select,
            selectionScope: scope,
            hasOwningInteraction: false
        ) == (scope == .object))
    }
}

@Test func measurementGateKeepsTheReadoutInEverySelectionScopeWhileMeasuring() {
    for scope in WorkspaceSelectionScope.allCases {
        #expect(WorkspaceMeasurementPresentationGate.showsBoundsReadout(
            selectedTool: .measure,
            selectionScope: scope,
            hasOwningInteraction: false
        ))
    }
}

@Test func measurementGateReadoutIsASupersetOfTheRulers() {
    for tool in ModelingTool.allCases {
        for scope in WorkspaceSelectionScope.allCases {
            for hasOwningInteraction in [false, true] {
                let rulers = WorkspaceMeasurementPresentationGate.showsBoundsRulers(
                    selectedTool: tool,
                    hasOwningInteraction: hasOwningInteraction
                )
                let readout = WorkspaceMeasurementPresentationGate.showsBoundsReadout(
                    selectedTool: tool,
                    selectionScope: scope,
                    hasOwningInteraction: hasOwningInteraction
                )
                #expect(!rulers || readout)
            }
        }
    }
}

@Test func measurementGateHidesBothFormsWhileAnInteractionOwnsTheViewport() {
    for tool in ModelingTool.allCases {
        #expect(!WorkspaceMeasurementPresentationGate.showsBoundsRulers(
            selectedTool: tool,
            hasOwningInteraction: true
        ))
        for scope in WorkspaceSelectionScope.allCases {
            #expect(!WorkspaceMeasurementPresentationGate.showsBoundsReadout(
                selectedTool: tool,
                selectionScope: scope,
                hasOwningInteraction: true
            ))
        }
    }
}
