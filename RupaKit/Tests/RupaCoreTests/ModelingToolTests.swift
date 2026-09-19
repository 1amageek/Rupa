import Testing
@testable import RupaCore

@Test func modelingToolDescribesEveryCase() {
    // The palette hint, the accessibility hint, the menu item and the line
    // reported on activation all read these, so a case that carries none of
    // them would leave one of those surfaces blank.
    for tool in ModelingTool.allCases {
        #expect(tool.title.isEmpty == false)
        #expect(tool.summary.isEmpty == false)
        #expect(tool.activationPrompt.isEmpty == false)
        #expect(tool.systemImage.isEmpty == false)
    }
}

@Test func modelingToolGivesTheFirstTenCasesAMenuKey() {
    // Ten digits are the whole budget a list that may grow can be given, and a
    // tool without a key shows no key rather than an invented one.
    let keys = ModelingTool.allCases.map(\.menuKeyEquivalent)
    let expected: [Character?] = (0..<ModelingTool.allCases.count).map { position in
        guard position < 10 else {
            return nil
        }
        return Character(String((position + 1) % 10))
    }

    #expect(keys == expected)
    #expect(keys.prefix(10).allSatisfy { $0 != nil })
    #expect(keys.dropFirst(10).allSatisfy { $0 == nil })
    #expect(Set(keys.compactMap { $0 }).count == min(10, ModelingTool.allCases.count))
}
