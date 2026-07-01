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
    #expect(siteWidthRow.sourceUsageTitle == "None")
    #expect(halfWidthRow.expression == "(siteWidth / 2)")
    #expect(halfWidthRow.resolvedTitle == "500 m")
    #expect(halfWidthRow.dependencyTitle == "siteWidth")
    #expect(halfWidthRow.dependentTitle == "None")
    #expect(halfWidthRow.sourceUsageTitle == "None")
}

@Test func workspaceParameterInspectorStateFormatsSourceFeatureUsages() throws {
    var document = DesignDocument.empty(named: "Parameter Feature Usage")
    try document.upsertParameter(
        name: "width",
        expression: .constant(.length(20.0, unit: .millimeter)),
        kind: .length
    )
    let width = try #require(
        document.cadDocument.parameters.parameters.values.first { $0.name == "width" }
    )
    let profileID = try document.createRectangleSketch(
        name: "Profile",
        plane: .xy,
        width: .reference(width.id),
        height: .constant(.length(8.0, unit: .millimeter))
    )
    try document.extrudeProfile(
        name: "Body",
        profile: ProfileReference(featureID: profileID),
        distance: .reference(width.id),
        direction: .normal
    )

    let result = ParameterListResult(
        document: document,
        generation: DocumentGeneration(2),
        dirty: true,
        diagnostics: []
    )
    let state = WorkspaceParameterInspectorState(result: result, displayUnit: .millimeter)
    let widthRow = try #require(state.rows.first { $0.name == "width" })

    #expect(widthRow.sourceUsageTitle.contains("Profile: sketch.entities["))
    #expect(widthRow.sourceUsageTitle.contains(".line."))
    #expect(widthRow.sourceUsageTitle.contains(".x"))
    #expect(widthRow.sourceUsageTitle.contains("Body: extrude.distance"))
}
