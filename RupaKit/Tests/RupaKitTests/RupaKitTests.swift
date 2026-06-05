import Testing
@testable import RupaKit

@Test func umbrellaExportsCoreTypes() async throws {
    let document = DesignDocument.empty()
    #expect(document.displayUnit == .millimeter)
}
