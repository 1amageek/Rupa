import Testing
@testable import RupaUI

@Test func commonWorkspaceInspectorValueAcceptsFiniteEqualValues() {
    #expect(commonWorkspaceInspectorValue([2.0, 2.0 + 5.0e-10]) == 2.0)
}

@Test func commonWorkspaceInspectorValueRejectsMixedAndInvalidValues() {
    #expect(commonWorkspaceInspectorValue([2.0, 2.1]) == nil)
    #expect(commonWorkspaceInspectorValue([2.0, .nan]) == nil)
    #expect(commonWorkspaceInspectorValue([]) == nil)
}
