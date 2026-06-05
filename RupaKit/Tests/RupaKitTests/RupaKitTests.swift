import Testing
@testable import RupaKit

@Test func umbrellaExportsCoreTypes() async throws {
    let document = RupaDocument.empty()
    #expect(document.displayUnit == .millimeter)
}
