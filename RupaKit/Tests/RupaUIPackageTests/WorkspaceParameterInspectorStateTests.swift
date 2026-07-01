import SwiftCAD
import Testing
@testable import RupaCore
@testable import RupaUI

@Test func workspaceParameterInspectorStateFormatsDependenciesAndResolvedValues() throws {
    var document = DesignDocument.empty(named: "Parameters")
    try document.upsertParameter(
        name: "siteWidth",
        expression: .constant(.length(1_000.0, unit: .meter)),
        kind: .length
    )
    let siteWidth = try #require(
        document.cadDocument.parameters.parameters.values.first { $0.name == "siteWidth" }
    )
    try document.upsertParameter(
        name: "halfWidth",
        expression: .divide(
            .reference(siteWidth.id),
            .constant(.scalar(2.0))
        ),
        kind: .length
    )

    let result = ParameterListResult(
        document: document,
        generation: DocumentGeneration(2),
        dirty: true,
        diagnostics: []
    )
    let state = WorkspaceParameterInspectorState(result: result, displayUnit: .millimeter)
    let siteWidthRow = try #require(state.rows.first { $0.name == "siteWidth" })
    let halfWidthRow = try #require(state.rows.first { $0.name == "halfWidth" })

    #expect(state.summaryTitle == "2 parameters.")
    #expect(siteWidthRow.resolvedTitle == "1 km")
    #expect(siteWidthRow.dependencyTitle == "None")
    #expect(siteWidthRow.dependentTitle == "halfWidth")
    #expect(halfWidthRow.expression == "(siteWidth / 2)")
    #expect(halfWidthRow.resolvedTitle == "500 m")
    #expect(halfWidthRow.dependencyTitle == "siteWidth")
    #expect(halfWidthRow.dependentTitle == "None")
}
