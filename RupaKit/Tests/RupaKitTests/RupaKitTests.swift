import Testing
@testable import RupaKit

@Test func umbrellaExportsCoreTypes() async throws {
    let workspaceState = WorkspaceState()
    #expect(workspaceState.displayUnit == .millimeter)
}
