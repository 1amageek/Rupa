import Testing
import RupaCore
@testable import RupaUI

@Test func workspaceSectionClippingModeMapsToOptionalRetainedSides() {
    #expect(WorkspaceSectionClippingMode.off.retainedSide == nil)
    #expect(WorkspaceSectionClippingMode.front.retainedSide == .front)
    #expect(WorkspaceSectionClippingMode.behind.retainedSide == .behind)
}

@Test func workspaceSectionClippingModeInitializesFromOptionalRetainedSides() {
    #expect(WorkspaceSectionClippingMode(retainedSide: nil) == .off)
    #expect(WorkspaceSectionClippingMode(retainedSide: .front) == .front)
    #expect(WorkspaceSectionClippingMode(retainedSide: .behind) == .behind)
}

@Test func workspaceSectionClippingModeExposesStableInspectorTitles() {
    #expect(WorkspaceSectionClippingMode.allCases.map(\.title) == [
        "Off",
        "Front",
        "Behind",
    ])
    #expect(WorkspaceSectionClippingMode.off.statusTitle == "Section only")
    #expect(WorkspaceSectionClippingMode.front.statusTitle == "Retain front")
    #expect(WorkspaceSectionClippingMode.behind.statusTitle == "Retain behind")
}
